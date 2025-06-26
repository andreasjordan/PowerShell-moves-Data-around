break
# This script needs PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_photoservice.ps1

# Some code to save code in the script
$PSDefaultParameterValues = @{
    'Invoke-SqlQuery:Connection'   = $photoservice.SqlConnection
    'Get-SqlDataReader:Connection' = $photoservice.SqlConnection
    'Write-SqlTable:Connection'    = $photoservice.SqlConnection
    'Invoke-PgQuery:Connection'    = $photoservice.PgConnection
    'Get-PgDataReader:Connection'  = $photoservice.PgConnection
    'Write-PgTable:Connection'     = $photoservice.PgConnection
    'Get-MioFileList:Connection'   = $photoservice.MioConnection
    'Get-MioFile:Connection'       = $photoservice.MioConnection
    'Remove-MioFile:Connection'    = $photoservice.MioConnection
}



################################
# Work with binary data (JEPG) #
################################


# To show that we can also upload binary data to databases - in this case PostgreSQL

$files = Get-ChildItem -Path ../data/photoservice/*.jpg
foreach ($file in $files) {
    $invokeParams = @{
        Query           = 'UPDATE photo SET image = :image WHERE name = :name'
        ParameterValues = @{
            name  = $file.Name
            image = Get-Content -Path $file.FullName -AsByteStream -Raw
        }
    }
    try {
        Invoke-PgQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import [$($file.Name)]: $_"
        break
    }
}


# Let's move the data from PostgreSQL to SQL Server

$createQuery = @'
CREATE TABLE dbo.photo
( id     INT
, name   VARCHAR(50)
, price  NUMERIC(5, 2)
, image  VARBINARY(MAX)
, CONSTRAINT photo_pk 
  PRIMARY KEY (id)
)
'@
Invoke-SqlQuery -Query $createQuery

$dataReader = Get-PgDataReader -Table photo
Write-SqlTable -Table dbo.photo -DataReader $dataReader


# Let's see if we really have the correct data

$photos = Invoke-SqlQuery -Query 'SELECT * FROM dbo.photo'
$photos | Format-Table
Set-Content -Path test.jpg -Value $photos[0].image -AsByteStream
Remove-Item -Path test.jpg





####################################################
# Transfer more data from PostgreSQL to SQL Server #
####################################################


# What data do we have?

Invoke-PgQuery -Query 'SELECT * FROM customer' | Select-Object -Last 5 | Format-Table
Invoke-PgQuery -Query 'SELECT * FROM order_header' | Select-Object -Last 5 | Format-Table
Invoke-PgQuery -Query 'SELECT * FROM order_detail' | Select-Object -Last 5 | Format-Table


# Create the tables

Invoke-SqlQuery -Query 'CREATE TABLE dbo.customer (id INT, firstname VARCHAR(50), surname VARCHAR(50), city VARCHAR(50), email VARCHAR(200), transfered_at DATETIME2, CONSTRAINT customer_pk PRIMARY KEY (id))' 
Invoke-SqlQuery -Query 'CREATE TABLE dbo.order_header (id INT, customer_id INT, created_at DATETIME2, updated_at DATETIME2, payment_uuid UNIQUEIDENTIFIER, shipment_uuid UNIQUEIDENTIFIER, CONSTRAINT order_header_pk PRIMARY KEY (id))' 
Invoke-SqlQuery -Query 'CREATE TABLE dbo.order_detail (order_id INT, photo_id INT, quantity INT, price NUMERIC(7, 2), CONSTRAINT order_detail_pk PRIMARY KEY (order_id, photo_id))' 



# Let's start with the customers
################################

# Transfer complete table every time

$dataReader = Get-PgDataReader -Query 'SELECT id, firstname, surname, city, email, NOW() AS transfered_at FROM customer'
Write-SqlTable -Table dbo.customer -DataReader $dataReader -TruncateTable

# A query for the SQL Server Management Studio:
# SELECT * FROM dbo.customer ORDER BY id DESC


# Transfer only new rows

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.customer' -As SingleValue
$readerParams = @{
    Query           = 'SELECT id, firstname, surname, city, email, NOW() AS transfered_at FROM customer WHERE id > :id'
    ParameterValues = @{ id = $targetId }
}
$dataReader = Get-PgDataReader @readerParams
Write-SqlTable -Table customer -DataReader $dataReader



# Let's transfer orders
#######################

# Transfer new orders

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM order_header' -As SingleValue
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_header WHERE id > :id' -ParameterValues @{ id = $targetId }
Write-SqlTable -Table dbo.order_header -DataReader $dataReader
Start-Sleep -Seconds 5
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_detail WHERE order_id > :id' -ParameterValues @{ id = $targetId }
Write-SqlTable -Table dbo.order_detail -DataReader $dataReader

# Some queries for the SQL Server Management Studio:
# SELECT * FROM dbo.order_header ORDER BY id DESC
# SELECT * FROM dbo.order_detail ORDER BY order_id DESC 


# Transfer new orders, only order_detail for transfered order_header

Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_header' 
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_detail' 

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$sourceId = Invoke-PgQuery -Query 'SELECT COALESCE(MAX(id), 0) FROM order_header' -As SingleValue
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_header WHERE id > :target_id AND id <= :source_id' -ParameterValues @{ target_id = $targetId ; source_id = $sourceId }
Write-SqlTable -Table order_header -DataReader $dataReader
Start-Sleep -Seconds 5
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_detail WHERE order_id > :target_id AND order_id <= :source_id' -ParameterValues @{ target_id = $targetId ; source_id = $sourceId }
Write-SqlTable -Table order_detail -DataReader $dataReader


# Transfer new orders, only order_detail for transfered order_header, within a transaction

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$sourceId = Invoke-PgQuery -Query 'SELECT COALESCE(MAX(id), 0) FROM order_header' -As SingleValue
$transaction = $photoservice.SqlConnection.BeginTransaction()
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_header WHERE id > :target_id AND id <= :source_id' -ParameterValues @{ target_id = $targetId ; source_id = $sourceId }
Write-SqlTable -Table dbo.order_header -DataReader $dataReader -Transaction $transaction
Start-Sleep -Seconds 5
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_detail WHERE order_id > :target_id AND order_id <= :source_id' -ParameterValues @{ target_id = $targetId ; source_id = $sourceId }
Write-SqlTable -Table dbo.order_detail -DataReader $dataReader -Transaction $transaction
Start-Sleep -Seconds 5
$transaction.Commit()
$transaction.Dispose()


# Transfer new orders, only order_detail for transfered order_header, within two transactions

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$sourceTransaction = $photoservice.PgConnection.BeginTransaction([System.Data.IsolationLevel]::RepeatableRead)
$targetTransaction = $photoservice.SqlConnection.BeginTransaction()
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_header WHERE id > :target_id' -ParameterValues @{ target_id = $targetId } -Transaction $sourceTransaction
Write-SqlTable -Table dbo.order_header -DataReader $dataReader -Transaction $targetTransaction
Start-Sleep -Seconds 5
$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_detail WHERE order_id > :target_id' -ParameterValues @{ target_id = $targetId } -Transaction $sourceTransaction
Write-SqlTable -Table dbo.order_detail -DataReader $dataReader -Transaction $targetTransaction
Start-Sleep -Seconds 5
$targetTransaction.Commit()
$targetTransaction.Dispose()
$sourceTransaction.Commit()
$sourceTransaction.Dispose()


# Transfer updated orders

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$targetLastUpdated = Invoke-SqlQuery -Query 'SELECT MAX(updated_at) FROM dbo.order_header' -As SingleValue
$updatedRows = Invoke-PgQuery -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $targetId ; updated_at = $targetLastUpdated }
foreach ($row in $updatedRows) {
    Invoke-SqlQuery -Query 'DELETE dbo.order_header WHERE id = @id' -ParameterValues @{ id = $row.id }
}
Write-SqlTable -Table dbo.order_header -Data $updatedRows


# Transfer updated orders, within a transaction

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$targetLastUpdated = Invoke-SqlQuery -Query 'SELECT MAX(updated_at) FROM dbo.order_header' -As SingleValue
$updatedRows = Invoke-PgQuery -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $targetId ; updated_at = $targetLastUpdated }
$transaction = $photoservice.SqlConnection.BeginTransaction()
foreach ($row in $updatedRows) {
    Invoke-SqlQuery -Query 'DELETE dbo.order_header WHERE id = @id' -ParameterValues @{ id = $row.id } -Transaction $transaction
}
Write-SqlTable -Table dbo.order_header -Data $updatedRows -Transaction $transaction
$transaction.Commit()
$transaction.Dispose()


# Transfer updated orders, with updates

$targetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$targetLastUpdated = Invoke-SqlQuery -Query 'SELECT MAX(updated_at) FROM dbo.order_header' -As SingleValue
$updatedRows = Invoke-PgQuery -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $targetId ; updated_at = $targetLastUpdated }
foreach ($row in $updatedRows) {
    Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.updated_at ; payment_uuid = $row.payment_uuid ; shipment_uuid = $row.shipment_uuid ; id = $row.id }
}


# Doing all transfers with transactions

$customerTargetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.customer' -As SingleValue
$orderTargetId = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
$orderTargetLastUpdated = Invoke-SqlQuery -Query 'SELECT MAX(updated_at) FROM dbo.order_header' -As SingleValue

$sourceTransaction = $photoservice.PgConnection.BeginTransaction([System.Data.IsolationLevel]::RepeatableRead)
$targetTransaction = $photoservice.SqlConnection.BeginTransaction()

$dataReader = Get-PgDataReader -Query 'SELECT id, firstname, surname, city, email, NOW() AS transfered_at FROM customer WHERE id > :id' -ParameterValues @{ id = $customerTargetId } -Transaction $sourceTransaction
Write-SqlTable -Table customer -DataReader $dataReader -Transaction $targetTransaction

$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_header WHERE id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
Write-SqlTable -Table dbo.order_header -DataReader $dataReader -Transaction $targetTransaction

$dataReader = Get-PgDataReader -Query 'SELECT * FROM order_detail WHERE order_id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
Write-SqlTable -Table dbo.order_detail -DataReader $dataReader -Transaction $targetTransaction

$updatedRows = Invoke-PgQuery -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $orderTargetId ; updated_at = $orderTargetLastUpdated } -Transaction $sourceTransaction
foreach ($row in $updatedRows) {
    Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.updated_at ; payment_uuid = $row.payment_uuid ; shipment_uuid = $row.shipment_uuid ; id = $row.id } -Transaction $targetTransaction
}

$targetTransaction.Commit()
$targetTransaction.Dispose()
$sourceTransaction.Commit()
$sourceTransaction.Dispose()


# To run this nonstop in the background:
# * Open pwsh (yes, needs to be PowerShell 7)
# * change the location to this demo folder
# * run .\04_photoservice_transfer_01.ps1





#########################################
# Transfer data from logging (or kafka) #
#########################################


Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.customer' 
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_header' 
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_detail' 


$fileList = Get-MioFileList
foreach ($file in $fileList) {
    # $file = $fileList[0]
    $content = Get-MioFile -Key $file.Key | ConvertFrom-Json
    foreach ($row in $content) {
        # $row = $content[2]
        if ($row.message -eq 'Added customer') {
            Write-SqlTable -Table customer -Data $row.Details -EnableException
        }
        if ($row.message -eq 'Added order header') {
            Write-SqlTable -Table order_header -Data $row.Details -EnableException
        }
        if ($row.message -eq 'Added order details') {
            Write-SqlTable -Table order_detail -Data $row.Details -EnableException
        }
        if ($row.message -eq 'Added payment') {
            Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.Details.UpdatedAt ; payment_uuid = [System.Guid]$row.Details.PaymentUuid.Guid ; id = $row.Details.OrderId } -EnableException
        }
        if ($row.message -eq 'Added shipment') {
            Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.Details.UpdatedAt ; shipment_uuid = [System.Guid]$row.Details.ShipmentUuid.Guid ; id = $row.Details.OrderId } -EnableException
        }
    }
    Remove-MioFile -Key $file.Key
}





################################################
# Transfer data from CDC (Change Data Capture) #
################################################


Invoke-SqlQuery -Query "EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'customer', @role_name = NULL"
Invoke-SqlQuery -Query "EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'order_header', @role_name = NULL"
Invoke-SqlQuery -Query "EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'order_detail', @role_name = NULL"

# https://learn.microsoft.com/en-us/sql/relational-databases/system-tables/cdc-capture-instance-ct-transact-sql?view=sql-server-ver16


Invoke-SqlQuery -Query "SELECT * FROM cdc.dbo_customer_CT" | Select-Object -Last 10




#############################################
# Bonus: Import Logging from files on MinIO #
#############################################


Invoke-SqlQuery -Query 'CREATE TABLE logging (id INT, timestamp DATETIME2, hostname VARCHAR(50), appname VARCHAR(50), component VARCHAR(50), level VARCHAR(50), message VARCHAR(500), details NVARCHAR(MAX), CONSTRAINT logging_pk PRIMARY KEY (id))' 

$fileList = Get-MioFileList
foreach ($file in $fileList) {
    $id = Invoke-SqlQuery -Query 'SELECT ISNULL(MAX(id), 0) FROM logging' -As SingleValue
    $content = Get-MioFile -Key $file.Key | ConvertFrom-Json
    $data = foreach ($row in $content) {
        if ($row.message -ne 'Starting Loop') {
            $id++
            [PSCustomObject]@{
                id        = $id
                timestamp = $row.timestamp
                hostname  = $row.hostname
                appname   = $row.appname
                component = $row.component
                level     = $row.level
                message   = $row.message
                details   = $( if ($row.details) { $row.details | ConvertTo-Json -Depth 9 -Compress } )
            }
        }
    }
    Write-SqlTable -Table logging -Data $data
    Remove-MioFile -Key $file.Key
}





########################################################################
# Bonus: Transfer documents from MongoDB to JSON columns in SQL Server #
########################################################################


# How to setup the Azure SQL Database will be published later...
$resourceGroupName = $env:AzureResourceGroupName
$serverName = $env:AzureServerName

$homeIP = (Invoke-WebRequest -Uri "http://ipinfo.io/json" -UseBasicParsing | ConvertFrom-Json).ip
$null = Set-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $serverName -Name AllowHome -StartIpAddress $homeIP -EndIpAddress $homeIP
$azureConnection = Connect-SqlInstance -Instance "$serverName.database.windows.net" -Credential $photoservice.SqlCredential -Database $photoservice.SqlDatabase

Invoke-SqlQuery -Connection $azureConnection -Query 'CREATE TABLE dbo.Orders (OrderData JSON)'

$ordersCollection = Read-MdbCollection -Connection $photoservice.MdbConnection -Collection Orders
# $ordersCollection[0] | ConvertTo-Json -Depth 4
$orders = $ordersCollection | ForEach-Object -Process { [PSCustomObject]@{ OrderData = $_ | ConvertTo-Json -Depth 4 -Compress } }
Write-SqlTable -Connection $azureConnection -Table dbo.Orders -Data $orders

$query = @'
SELECT PhotoData.PhotoId
     , PhotoData.Name
     , PhotoData.Price
     , COUNT(*) AS Quantity
  FROM Orders
 CROSS APPLY OPENJSON(CAST(OrderData AS NVARCHAR(MAX)), '$.Photos')
             WITH ( Quantity INT
                  , Photo    NVARCHAR(MAX) AS JSON
                  ) AS PhotoWrapper
 CROSS APPLY OPENJSON(PhotoWrapper.Photo)
             WITH ( PhotoId INT
                  , Name    NVARCHAR(255)
                  , Price   DECIMAL(10,2)
                  ) AS PhotoData
 GROUP BY PhotoData.PhotoId
        , PhotoData.Name
        , PhotoData.Price
 ORDER BY Quantity DESC
'@
Invoke-SqlQuery -Connection $azureConnection -Query $query





<####################################################################################################

Key takeaways:

* Binary data is just data, nothing special
* Transferring only new or changed data requires some considerations
* Main question: How to identify the relevant rows
* Transactions help to get consistent data
* Using event data is sometimes an option

####################################################################################################>





# Cleanup:
Invoke-SqlQuery -Query 'DROP TABLE dbo.customer' 
Invoke-SqlQuery -Query 'DROP TABLE dbo.order_header' 
Invoke-SqlQuery -Query 'DROP TABLE dbo.order_detail' 
Invoke-SqlQuery -Connection $azureConnection -Query 'DROP TABLE dbo.Orders'
