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
# The topic is deliberately not emptied. The bucket was, because a log archive that outlives the
# tables it describes is just confusing - but a topic keeps its history on purpose, and demo 6
# reads across restarts. The offsets, not the topic, are what a reader starts from.


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
            created_at    = [datetime]::Now
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
        Add-LoggingEvent -Component Order -Message 'Added order header' -Details $orderHeader

        Write-PgTable -Connection $dbConfig.PgConnection -Table order_detail -Data $orderDetails -Transaction $transaction
        Add-LoggingEvent -Component Order -Message 'Added order details' -Details $orderDetails

        $transaction.Commit()

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
                UpdatedAt   = [datetime]::Now
            }
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, payment_uuid = :payment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid ; id = $payment.OrderId }
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, payment_uuid) VALUES (:order_id, :updated_at, :payment_uuid)' -ParameterValues @{ order_id = $payment.OrderId ; updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid }
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
                UpdatedAt    = [datetime]::Now
            }
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, shipment_uuid = :shipment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid ; id = $shipment.OrderId }
            Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, shipment_uuid) VALUES (:order_id, :updated_at, :shipment_uuid)' -ParameterValues @{ order_id = $shipment.OrderId ; updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid }
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
