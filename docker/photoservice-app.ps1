$ErrorActionPreference = 'Stop'

Import-Module PSFramework, Mdbc
Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path ./lib/*-Pg*.ps1, ./lib/*-Mdb*.ps1, ./lib/*-Mio*.ps1)) { . $file.FullName }
Write-PSFMessage -Level Host -Message 'Importing database libraries'
Import-PgLibrary
$PSDefaultParameterValues = @{
    "*-Pg*:EnableException"  = $true
    "*-Mdb*:EnableException" = $true
}

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
    MioInstance = 'minio'
    MioUser     = 'photoservice'
    MioPassword = 'Passw0rd!'
    MioBucket   = 'photoservice'
}
$dbConfig.PgCredential = [PSCredential]::new($dbConfig.PgUser, ($dbConfig.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$dbConfig.MdbCredential = [PSCredential]::new($dbConfig.MdbUser, ($dbConfig.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))
$dbConfig.MioCredential = [PSCredential]::new($dbConfig.MioUser, ($dbConfig.MioPassword | ConvertTo-SecureString -AsPlainText -Force))

while ($true) {
    try {
        Write-PSFMessage -Level Host -Message 'Connecting to PostgreSQL'
        $dbConfig.PgConnection = Connect-PgInstance -Instance $dbConfig.PgInstance -Credential $dbConfig.PgCredential -Database $dbConfig.PgDatabase
        Write-PSFMessage -Level Host -Message 'Connecting to MongoDB'
        $dbConfig.MdbConnection = Connect-MdbInstance -Instance $dbConfig.MdbInstance -Credential $dbConfig.MdbCredential -Database $dbConfig.MdbDatabase
        Write-PSFMessage -Level Host -Message 'Connecting to MinIO'
        $dbConfig.MioConnection = Connect-MioInstance -Instance $dbConfig.MioInstance -Credential $dbConfig.MioCredential -Bucket $dbConfig.MioBucket
        break
    } catch {
        Write-PSFMessage -Level Warning -Message "Connection failed: $_"
        Start-Sleep -Seconds 10
    }
}

$photos = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query "SELECT id, name, price FROM photo"

$newCustomer = @{
    DelaySec = 60
    NextRun  = Get-Date
    NextId   = 1
}

$newOrder = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddMinutes(10)
    NextId   = 1
}

$newPayment = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddMinutes(15)
}

$newShipment = @{
    DelaySec = 1
    NextRun  = (Get-Date).AddMinutes(20)
}

$newLogging = @{
    DelaySec = 120
    NextRun  = Get-Date
}

$loggingEvents = [System.Collections.ArrayList]::new()
function Add-LoggingEvent {
    param (
        [string]$Level = 'INFO',
        [string]$Component = 'Main',
        [string]$Message,
        [object]$Details
    )
    $loggingEvent = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        Hostname  = hostname
        Appname   = 'PictureService'
        Component = $Component
        Level     = $Level
        Message   = $Message
    }
    if ($Details) {
        $loggingEvent.Details = $Details
    }
    $null = $loggingEvents.Add($loggingEvent)
}


Write-PSFMessage -Level Host -Message 'Starting Loop'
while ($true) {
    Add-LoggingEvent -Message 'Starting Loop'

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
        Add-LoggingEvent -Component Order -Message 'Added order to MongoDB collection' -Details $orderDocument

        $newOrder.NextId++
        $newOrder.NextRun = (Get-Date).AddSeconds($newOrder.DelaySec)
        Add-LoggingEvent -Component Order -Message "Scheduled next order with id $($newOrder.NextId) for $($newOrder.NextRun)"
    }

    if ((Get-Date) -gt $newPayment.NextRun) {
        Add-LoggingEvent -Component Payment -Message 'Starting NewPayment'
        
        $payment = [PSCustomObject]@{
            OrderId     = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'SELECT id FROM order_header WHERE payment_uuid IS NULL ORDER BY RANDOM() LIMIT 1' -As SingleValue
            PaymentUuid = New-Guid
            UpdatedAt   = [datetime]::Now
        }
        Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, payment_uuid = :payment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid ; id = $payment.OrderId }
        Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, payment_uuid) VALUES (:order_id, :updated_at, :payment_uuid)' -ParameterValues @{ order_id = $payment.OrderId ; updated_at = $payment.UpdatedAt ; payment_uuid = $payment.PaymentUuid }
        Add-LoggingEvent -Component Payment -Message 'Added payment' -Details $payment

        $newPayment.NextRun = (Get-Date).AddSeconds($newPayment.DelaySec)
        Add-LoggingEvent -Component Payment -Message "Scheduled next payment for $($newPayment.NextRun)"
    }

    if ((Get-Date) -gt $newShipment.NextRun) {
        Add-LoggingEvent -Component Shipment -Message 'Starting NewShipment'
        
        $shipment = [PSCustomObject]@{
            OrderId      = Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'SELECT id FROM order_header WHERE payment_uuid IS NOT NULL AND shipment_uuid IS NULL ORDER BY RANDOM() LIMIT 1' -As SingleValue
            ShipmentUuid = New-Guid
            UpdatedAt    = [datetime]::Now
        }
        Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'UPDATE order_header SET updated_at = :updated_at, shipment_uuid = :shipment_uuid WHERE id = :id' -ParameterValues @{ updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid ; id = $shipment.OrderId }
        Invoke-PgQuery -Connection $dbConfig.PgConnection -Query 'INSERT INTO order_event (order_id, updated_at, shipment_uuid) VALUES (:order_id, :updated_at, :shipment_uuid)' -ParameterValues @{ order_id = $shipment.OrderId ; updated_at = $shipment.UpdatedAt ; shipment_uuid = $shipment.ShipmentUuid }
        Add-LoggingEvent -Component Shipment -Message 'Added shipment' -Details $shipment

        $newShipment.NextRun = (Get-Date).AddSeconds($newShipment.DelaySec)
        Add-LoggingEvent -Component Shipment -Message "Scheduled next shipment for $($newShipment.NextRun)"
    }

    if ((Get-Date) -gt $newLogging.NextRun) {
        Add-LoggingEvent -Message 'Starting NewLogging'

        $loggingKey = '{0}/{1}/{2}.log' -f $(hostname), (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"), (Get-Date).ToUniversalTime().ToString("HH-mm-ss")
        $loggingContent = $loggingEvents | ConvertTo-Json -Depth 9 -Compress
        Set-MioFile -Connection $dbConfig.MioConnection -Key $loggingKey -Content $loggingContent
        $loggingEvents.Clear()

        $newLogging.NextRun = (Get-Date).AddSeconds($newLogging.DelaySec)
        Add-LoggingEvent -Component Logging -Message "Scheduled next logging archive for $($newLogging.NextRun)"
    }

    Start-Sleep -Milliseconds 100
}
