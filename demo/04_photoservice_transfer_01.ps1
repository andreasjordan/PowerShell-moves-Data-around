$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_photoservice.ps1

while (1) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $customerTargetId = Invoke-SqlQuery -Connection $photoservice.SqlConnection -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.customer' -As SingleValue
    $orderTargetId = Invoke-SqlQuery -Connection $photoservice.SqlConnection -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.order_header' -As SingleValue
    $orderTargetLastUpdated = Invoke-SqlQuery -Connection $photoservice.SqlConnection -Query 'SELECT MAX(updated_at) FROM dbo.order_header' -As SingleValue

    Write-PSFMessage -Level Host -Message "Starting transfer with customerTargetId $customerTargetId, orderTargetId $orderTargetId and orderTargetLastUpdated $orderTargetLastUpdated"

    $sourceTransaction = $photoservice.PgConnection.BeginTransaction([System.Data.IsolationLevel]::RepeatableRead)
    $targetTransaction = $photoservice.SqlConnection.BeginTransaction()

    $dataReader = Get-PgDataReader -Connection $photoservice.PgConnection -Query 'SELECT id, firstname, surname, city, email, NOW() AS transfered_at FROM customer WHERE id > :id' -ParameterValues @{ id = $customerTargetId } -Transaction $sourceTransaction
    Write-SqlTable -Connection $photoservice.SqlConnection -Table customer -DataReader $dataReader -Transaction $targetTransaction

    $dataReader = Get-PgDataReader -Connection $photoservice.PgConnection -Query 'SELECT * FROM order_header WHERE id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
    Write-SqlTable -Connection $photoservice.SqlConnection -Table dbo.order_header -DataReader $dataReader -Transaction $targetTransaction

    $dataReader = Get-PgDataReader -Connection $photoservice.PgConnection -Query 'SELECT * FROM order_detail WHERE order_id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
    Write-SqlTable -Connection $photoservice.SqlConnection -Table dbo.order_detail -DataReader $dataReader -Transaction $targetTransaction

    $updatedRows = Invoke-PgQuery -Connection $photoservice.PgConnection -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $orderTargetId ; updated_at = $orderTargetLastUpdated } -Transaction $sourceTransaction
    foreach ($row in $updatedRows) {
        Invoke-SqlQuery -Connection $photoservice.SqlConnection -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.updated_at ; payment_uuid = $row.payment_uuid ; shipment_uuid = $row.shipment_uuid ; id = $row.id } -Transaction $targetTransaction
    }

    $targetTransaction.Commit()
    $targetTransaction.Dispose()
    $sourceTransaction.Commit()
    $sourceTransaction.Dispose()

    $stopwatch.Stop()
    Write-PSFMessage -Level Host -Message "Transfer completed after $($stopwatch.ElapsedMilliseconds) Milliseconds"

    Start-Sleep -Seconds 10
}
