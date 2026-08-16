$ErrorActionPreference = 'Stop'

Import-Module PSFramework, Mdbc
Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path ./lib/*-Pg*.ps1, ./lib/*-Mdb*.ps1, ./lib/*-Kfk*.ps1)) { . $file.FullName }
Write-PSFMessage -Level Host -Message 'Importing database libraries'
Import-PgLibrary
Import-KfkLibrary
$PSDefaultParameterValues = @{
    "*-Pg*:EnableException"  = $true
    "*-Mdb*:EnableException" = $true
    "*-Kfk*:EnableException" = $true
}

# The topic every logging event goes to, and the one demo/06_eventstreaming.ps1 reads
$topic = 'photoservice.events'

Write-PSFMessage -Level Host -Message 'Reading sample data from files'
$customerSource = Get-Content -Path ./CustomerSource.json | ConvertFrom-Json

Write-PSFMessage -Level Host -Message 'Setting up variables and connections'
$dbConfig = @{
    PgInstance  = 'postgres'
    PgUser      = 'photoservice'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'photoservice'
    MdbInstance = 'mongo'
    MdbUser     = 'photoservice'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'photoservice'
    # The broker is reached over the compose network here, not on the port published to Windows.
    # That is why the container advertises two listeners - see docker-compose.yaml.
    KfkInstance = 'redpanda:9092'
}
$dbConfig.PgCredential = [PSCredential]::new($dbConfig.PgUser, ($dbConfig.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$dbConfig.MdbCredential = [PSCredential]::new($dbConfig.MdbUser, ($dbConfig.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))

while ($true) {
    try {
        Write-PSFMessage -Level Host -Message 'Connecting to PostgreSQL'
        $dbConfig.PgConnection = Connect-PgInstance -Instance $dbConfig.PgInstance -Credential $dbConfig.PgCredential -Database $dbConfig.PgDatabase
        Write-PSFMessage -Level Host -Message 'Connecting to MongoDB'
        $dbConfig.MdbConnection = Connect-MdbInstance -Instance $dbConfig.MdbInstance -Credential $dbConfig.MdbCredential -Database $dbConfig.MdbDatabase
        Write-PSFMessage -Level Host -Message 'Connecting to Kafka'
        $dbConfig.KfkProducer = Connect-KfkProducer -Instance $dbConfig.KfkInstance
        break
    } catch {
        Write-PSFMessage -Level Warning -Message "Connection failed: $_"
        Start-Sleep -Seconds 10
    }
}

Write-PSFMessage -Level Host -Message 'Removing data from previous run'
Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "TRUNCATE TABLE order_event"
Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "TRUNCATE TABLE order_detail"
Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "TRUNCATE TABLE order_header"
Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "TRUNCATE TABLE customer"
Remove-MdbCollection -Connection $dbConfig.MdbConnection -Collection Orders
# The topic goes with the tables, and this line used to say the opposite - that a topic keeps its
# history on purpose. It does, but not across restarts of the thing that writes it: the ids start
# again at 1 here, so a topic that survives holds three customers with id 1 and demo 6's replay
# dies on a primary key violation. Emptying it makes the reset complete rather than half done.
#
# The history demo 6 teaches is across *readers*, not across application starts, and that is
# untouched: a new group id still replays the whole topic, and the offsets are per group.
Remove-KfkTopic -Instance $dbConfig.KfkInstance -Topic $topic


Write-PSFMessage -Level Host -Message 'Reading photo data'
$photos = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "SELECT id, name, price FROM photo"


# The schedule, ten times faster than it used to be
#
# What the demo teaches is the order - a customer, then an order, then a payment, then a shipment -
# and nothing in that story needed the gaps to be ten, fifteen and twenty minutes. They were, and it
# made demo 4 empty for twenty minutes after every container start and after every switch between
# the two repositories, which is most of what made switching expensive.
#
# The customer interval is scaled with the offsets and not left alone, because the proportion is
# what matters: at 6 seconds each, ten customers exist by the time the first order is placed, which
# is exactly what 60 seconds gave against a ten-minute offset. The one-second intervals stay as they
# are - they cannot be scaled down meaningfully, and they were already the fast end of this.
#
# Keep this schedule in step with docker/photoservice-app.py in the sibling repository.
Write-PSFMessage -Level Host -Message 'Setting up state objects'
$newCustomer = @{
    DelaySec = 6
    NextRun  = Get-Date
    NextId   = 1
}

$newOrder = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddSeconds(60)
    NextId   = 1
}

$newPayment = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddSeconds(90)
}

$newShipment = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddSeconds(120)
}

# Every timestamp that is stored goes through here, and the SpecifyKind is the whole point of it.
#
# Npgsql converts a DateTime whose Kind is Local into UTC on the way into a TIMESTAMP column, so a
# shop that took an order at 18:23 stored 16:23 and pgAdmin showed a time two hours in the past for
# no visible reason. Unspecified means "wall clock, no time zone", which is exactly what the column
# is - and it is what psycopg writes for the naive datetime.now() in the sibling's
# photoservice-app.py, so the two repositories now hold the same value for the same order.
#
# It also settles it for the topic: with no Kind, ConvertTo-Json writes 2026-08-15T18:23:56.418
# instead of the same instant with a +02:00 offset on the end, so a replay through Kafka and a
# direct PostgreSQL to SQL Server transfer land the same value.
#
# Local time is a deliberate choice for a demo - the clock on the wall is the clock on the slide.
# The Timestamp of the logging event below stays UTC, because the sibling's is UTC too.
#
# And it is truncated to milliseconds, because that is what the columns are. [datetime]::Now has
# a hundred nanoseconds of resolution, TIMESTAMP(3) keeps three digits and rounds - so the topic
# carried 09:46:49.0523691 while PostgreSQL held 09:46:49.052, and a replay through demo 6 landed
# a different value in SQL Server than the direct transfer in demo 4 did. Sub-millisecond, on
# every row. Handing over what the column can actually store removes the question.
function Get-LocalTimestamp {
    $now = [datetime]::Now
    [datetime]::SpecifyKind($now.AddTicks(-($now.Ticks % [timespan]::TicksPerMillisecond)), 'Unspecified')
}


# An event goes straight to the Kafka topic, where demo/06_eventstreaming.ps1 reads it. It used to
# be collected in a list and written to a MinIO bucket as a log archive every twelve seconds, which
# is why there was a schedule for it; a topic needs no schedule and no batching.
#
# Only events that carry -Details are sent. The ones without are scheduling chatter, and the
# archive only had them because an archive is a log file. A topic somebody is going to replay is
# better off without them. This is the shape docker/photoservice-app.py uses - keep the two in step.
function Add-LoggingEvent {
    param (
        [string]$Level = 'INFO',
        [string]$Component = 'Main',
        [string]$Message,
        [object]$Details
    )
    Write-PSFMessage -Level Host -Message "[$Component] $Message"

    if (-not $Details) {
        return
    }

    $loggingEvent = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        Hostname  = hostname
        Appname   = 'PhotoService'
        Component = $Component
        Level     = $Level
        Message   = $Message
        Details   = $Details
    }
    Write-KfkTopic -Connection $dbConfig.KfkProducer -Topic $topic -Data ([PSCustomObject]$loggingEvent)
}


Write-PSFMessage -Level Host -Message 'Starting Loop'
while ($true) {
    # No event for the loop itself. There used to be one, logged every 100 milliseconds, and it
    # only made sense while these went into a log archive - demo 4 then had to skip it by name
    # when reading the archive back. docker/photoservice-app.py has never had it.

    if ((Get-Date) -gt $newCustomer.NextRun) {
        Add-LoggingEvent -Component Customer -Message 'Starting NewCustomer'

        $firstname = $customerSource.Firstnames[$(Get-Random -Minimum 0 -Maximum $($customerSource.Firstnames.Count))]
        $surname = $customerSource.Surnames[$(Get-Random -Minimum 0 -Maximum $($customerSource.Surnames.Count))]
        $city = $customerSource.Cities[$(Get-Random -Minimum 0 -Maximum $($customerSource.Cities.Count))]
        $email = '{0}.{1}@{2}.de' -f $firstname, $surname, $city.Replace('ä','ae').Replace('ö','oe').Replace('ü','ue').Replace(' ','').ToLower()
        $customer = [PSCustomObject]@{
            id         = $newCustomer.NextId
            firstname  = $firstname
            surname    = $surname
            city       = $city
            email      = $email
        }
        Write-PgTable -Connection $dbConfig.PgConnection -Table customer -Data $customer
        Add-LoggingEvent -Component Customer -Message 'Added customer' -Details $customer

        $newCustomer.NextId++
        $newCustomer.NextRun = (Get-Date).AddSeconds($newCustomer.DelaySec)
        Add-LoggingEvent -Component Customer -Message "Scheduled next customer with id $($newCustomer.NextId) for $($newCustomer.NextRun)"
    }

    if ((Get-Date) -gt $newOrder.NextRun) {
        Add-LoggingEvent -Message 'Starting NewOrder'

        $orderHeader = [PSCustomObject]@{
            id            = $newOrder.NextId
            customer_id   = [int](Get-Random -Minimum 1 -Maximum $newCustomer.NextId)
            created_at    = Get-LocalTimestamp
            updated_at    = $null
            payment_uuid  = $null
            shipment_uuid = $null
        }

        $numberOfPhotos = Get-Random -Minimum 1 -Maximum 50
        Add-LoggingEvent -Component Order -Message "Order will contain $numberOfPhotos photos"
        $listOfPhotoIds = 1..$numberOfPhotos | ForEach-Object { Get-Random -Minimum 1 -Maximum $($photos.Count + 1) } | Group-Object -AsHashTable
        $orderDetails = foreach ($photo in $photos) {
            if ($listOfPhotoIds[$photo.id]) {
                [PSCustomObject]@{
                    order_id = $orderHeader.id
                    photo_id = $photo.id
                    quantity = $listOfPhotoIds[$photo.id].Count
                    price    = $listOfPhotoIds[$photo.id].Count * $photo.price
                }
            }
        }

        $transaction = $dbConfig.PgConnection.BeginTransaction()

        Write-PgTable -Connection $dbConfig.PgConnection -Table order_header -Data $orderHeader -Transaction $transaction
        Write-PgTable -Connection $dbConfig.PgConnection -Table order_detail -Data $orderDetails -Transaction $transaction

        $transaction.Commit()

        # Announced after the commit, not before it. An event that says a thing happened, sent
        # while the transaction that did it could still roll back, is the oldest mistake in this
        # subject - and demo 6 is about believing these events. Measured before this moved: the
        # topic held 242 order headers and PostgreSQL 241, because the application was stopped
        # between the two.
        Add-LoggingEvent -Component Order -Message 'Added order header' -Details $orderHeader
        Add-LoggingEvent -Component Order -Message 'Added order details' -Details $orderDetails

        $customer = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'SELECT * FROM customer WHERE id = :id' -ParameterValues @{ id = $orderHeader.customer_id }
        $price = 0
        $orderDetailsDocument = foreach($detail in $orderDetails) {
            $photo = $photos | Where-Object Id -eq $detail.photo_id
            $price += $photo.price * $detail.quantity
            [PSCustomObject]@{
                Quantity = $detail.quantity
                Photo    = [PSCustomObject]@{
                    PhotoId = $photo.id
                    Name    = $photo.name
                    Price   = $photo.price
                }
            }
        }
        $orderDocument = [PSCustomObject]@{
            OrderId   = $orderHeader.id
            CreatedAt = $orderHeader.created_at
            Customer  = [PSCustomObject]@{
                CustomerId = $customer.id
                FirstName  = $customer.firstname
                SurName    = $customer.surname
                City       = $customer.city
                EMail      = $customer.email
            }
            Photos    = $orderDetailsDocument
            Price     = $price
        }
        Write-MdbCollection -Connection $dbConfig.MdbConnection -Collection Orders -Data $orderDocument
        # No details on purpose, so this stays a console line and does not reach the topic. The
        # whole order document is already on it as a header and its details, and the sibling's
        # photoservice-app.py passes no details here either - the two topics have to match.
        Add-LoggingEvent -Component Order -Message "Added order $($orderHeader.id) to the MongoDB collection"

        $newOrder.NextId++
        $newOrder.NextRun = (Get-Date).AddSeconds($newOrder.DelaySec)
        Add-LoggingEvent -Component Order -Message "Scheduled next order with id $($newOrder.NextId) for $($newOrder.NextRun)"
    }

    if ((Get-Date) -gt $newPayment.NextRun) {
        Add-LoggingEvent -Component Payment -Message 'Starting NewPayment'

        $orderId = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'SELECT id FROM order_header WHERE payment_uuid IS NULL ORDER BY RANDOM() LIMIT 1' -As SingleValue

        # Every order may already be paid for - the payment loop runs as often as the order loop and
        # can catch up with it. Without this check the UPDATE matches no row and the INSERT writes an
        # order_event whose order_id is NULL, which every later join has to cope with.
        if ($null -ne $orderId) {
            $payment = [PSCustomObject]@{
                OrderId     = $orderId
                PaymentUuid = New-Guid
                UpdatedAt   = Get-LocalTimestamp
            }
            # The change and the outbox row are one unit of work, and that is the whole point of an
            # outbox: if the order was not paid for, there is no row claiming it was. These used to
            # be two separate autocommitted statements, so a crash between them left a paid order
            # with nothing to say so - and demo 6 had to explain the gap instead of the pattern.
            $transaction = $dbConfig.PgConnection.BeginTransaction()
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, payment_uuid = :payment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid ; id = $payment.OrderId } -Transaction $transaction
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, payment_uuid) VALUES (:order_id, :updated_at, :payment_uuid)' -ParameterValues @{ order_id = $payment.OrderId ; updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid } -Transaction $transaction
            $transaction.Commit()

            # After the commit, for the reason the order block above gives
            Add-LoggingEvent -Component Payment -Message 'Added payment' -Details $payment
        }

        $newPayment.NextRun = (Get-Date).AddSeconds($newPayment.DelaySec)
        Add-LoggingEvent -Component Payment -Message "Scheduled next payment for $($newPayment.NextRun)"
    }

    if ((Get-Date) -gt $newShipment.NextRun) {
        Add-LoggingEvent -Component Shipment -Message 'Starting NewShipment'

        $orderId = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'SELECT id FROM order_header WHERE payment_uuid IS NOT NULL AND shipment_uuid IS NULL ORDER BY RANDOM() LIMIT 1' -As SingleValue

        # Same hole as the payment block above: everything paid for may already have shipped
        if ($null -ne $orderId) {
            $shipment = [PSCustomObject]@{
                OrderId      = $orderId
                ShipmentUuid = New-Guid
                UpdatedAt    = Get-LocalTimestamp
            }
            # One unit of work, the same as the payment block above
            $transaction = $dbConfig.PgConnection.BeginTransaction()
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, shipment_uuid = :shipment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid ; id = $shipment.OrderId } -Transaction $transaction
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, shipment_uuid) VALUES (:order_id, :updated_at, :shipment_uuid)' -ParameterValues @{ order_id = $shipment.OrderId ; updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid } -Transaction $transaction
            $transaction.Commit()

            Add-LoggingEvent -Component Shipment -Message 'Added shipment' -Details $shipment
        }

        $newShipment.NextRun = (Get-Date).AddSeconds($newShipment.DelaySec)
        Add-LoggingEvent -Component Shipment -Message "Scheduled next shipment for $($newShipment.NextRun)"
    }

    # There is no logging block here any more. Events used to be collected and written to the
    # bucket as an archive every twelve seconds, which is why they arrived in demo 4 in bursts.
    # Add-LoggingEvent produces to the topic as it happens, so there is nothing left to schedule.

    Start-Sleep -Milliseconds 100
}
