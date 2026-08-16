# Reproduces the PhotoService numbers from AGENTS.md: 24 images, 43.5 MB, byte-identical by MD5 and
# length, and a transfer whose first pass carries the backlog while later passes do not.
#
# Needs SQL Server, PostgreSQL and the photoservice container running. The second half has nothing
# to find until the shop has been up for about two minutes, and says so rather than failing.
#
# Loads the images into the PostgreSQL photo table, which is what demo 4's first section does and
# what leaves that table in its post-demo state. Everything else is created as Verify_* and dropped.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'PhotoService' -ReportPath $ReportPath

Push-Location -Path $PSScriptRoot/../demo
try {
    . ./init_photoservice.ps1 *> $null
    $PSDefaultParameterValues = @{
        '*-Sql*:EnableException' = $true
        '*-Pg*:EnableException'  = $true
    }
    $sql = $photoservice.SqlConnection
    $pg = $photoservice.PgConnection

    ##########################################################################
    # The photos
    ##########################################################################

    $md5 = [System.Security.Cryptography.MD5]::Create()
    $files = @(Get-ChildItem -Path ../data/photoservice/*.jpg)
    $totalBytes = ($files | Measure-Object Length -Sum).Sum
    Test-Fact -Name '24 jpg files on disk' -Ok ($files.Count -eq 24) -Detail "$($files.Count) files"
    Test-Fact -Name 'about 43.5 MB on disk' -Ok ([math]::Abs($totalBytes / 1MB - 43.5) -lt 0.5) -Detail ('{0:N1} MB / {1} bytes' -f ($totalBytes / 1MB), $totalBytes)

    # demo 4's first section, driven the way the demo drives it
    foreach ($file in $files) {
        Invoke-PgQuery -Connection $pg -Query 'UPDATE photo SET image = :image WHERE name = :name' -ParameterValues @{
            name  = $file.Name
            image = Get-Content -Path $file.FullName -AsByteStream -Raw
        }
    }

    # The photo rows exist with a NULL image until the loop above runs, so a comparison that skipped
    # this would be comparing nothing against nothing - which is how an MD5 check passed for the
    # wrong reason once.
    $notNull = Invoke-PgQuery -Connection $pg -Query 'SELECT COUNT(*) FROM photo WHERE image IS NOT NULL' -As SingleValue
    Test-Fact -Name '24 non-NULL images in PostgreSQL' -Ok ($notNull -eq 24) -Detail "$notNull non-NULL"

    Invoke-SqlQuery -Connection $sql -Query 'DROP TABLE IF EXISTS dbo.Verify_photo'
    Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_photo (id INT, name VARCHAR(50), price NUMERIC(5, 2), image VARBINARY(MAX), CONSTRAINT Verify_photo_pk PRIMARY KEY (id))'
    try {
        $dataReader = Get-PgDataReader -Connection $pg -Table photo
        Write-SqlTable -Connection $sql -Table dbo.Verify_photo -DataReader $dataReader

        $pgRows = Invoke-PgQuery -Connection $pg -Query 'SELECT name, image FROM photo ORDER BY name'
        $sqlRows = Invoke-SqlQuery -Connection $sql -Query 'SELECT name, image FROM dbo.Verify_photo ORDER BY name'

        $lengthDiffer = 0; $hashDiffer = 0; $nullSeen = 0; $compared = 0
        foreach ($file in ($files | Sort-Object Name)) {
            $fileBytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $pgImage = ($pgRows | Where-Object name -eq $file.Name).image
            $sqlImage = ($sqlRows | Where-Object name -eq $file.Name).image
            if ($null -eq $pgImage -or $null -eq $sqlImage) { $nullSeen++ ; continue }
            $compared++
            if ($fileBytes.Length -ne $pgImage.Length -or $fileBytes.Length -ne $sqlImage.Length) { $lengthDiffer++ }
            $hFile = [BitConverter]::ToString($md5.ComputeHash($fileBytes))
            if ($hFile -ne [BitConverter]::ToString($md5.ComputeHash($pgImage)) -or
                $hFile -ne [BitConverter]::ToString($md5.ComputeHash($sqlImage))) { $hashDiffer++ }
        }
        Test-Fact -Name 'no NULL image reached the comparison' -Ok ($nullSeen -eq 0) -Detail "$nullSeen NULL"
        Test-Fact -Name 'all 24 were actually compared' -Ok ($compared -eq 24) -Detail "$compared compared"
        Test-Fact -Name 'length identical: file, PostgreSQL, SQL Server' -Ok ($lengthDiffer -eq 0) -Detail "$lengthDiffer differ"
        Test-Fact -Name 'MD5 identical: file, PostgreSQL, SQL Server' -Ok ($hashDiffer -eq 0) -Detail "$hashDiffer differ"
    } finally {
        Invoke-SqlQuery -Connection $sql -Query 'DROP TABLE IF EXISTS dbo.Verify_photo'
    }

    ##########################################################################
    # The incremental transfer
    ##########################################################################

    $sourceOrders = Invoke-PgQuery -Connection $pg -Query 'SELECT COUNT(*) FROM order_header' -As SingleValue
    if ($sourceOrders -lt 1) {
        Test-Fact -Name 'the shop has produced orders to transfer' -Ok $false -Detail 'none yet - the first order is 60 s after the container starts'
    } else {
        Test-Fact -Name 'the shop has produced orders to transfer' -Ok $true -Detail "$sourceOrders order headers in PostgreSQL"

        foreach ($table in 'dbo.Verify_customer', 'dbo.Verify_order_header', 'dbo.Verify_order_detail') {
            Invoke-SqlQuery -Connection $sql -Query "DROP TABLE IF EXISTS $table"
        }
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_customer (id INT, firstname VARCHAR(50), surname VARCHAR(50), city VARCHAR(50), email VARCHAR(200), transfered_at DATETIME2, CONSTRAINT Verify_customer_pk PRIMARY KEY (id))'
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_order_header (id INT, customer_id INT, created_at DATETIME2, updated_at DATETIME2, payment_uuid UNIQUEIDENTIFIER, shipment_uuid UNIQUEIDENTIFIER, CONSTRAINT Verify_order_header_pk PRIMARY KEY (id))'
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_order_detail (order_id INT, photo_id INT, quantity INT, price NUMERIC(7, 2), CONSTRAINT Verify_order_detail_pk PRIMARY KEY (order_id, photo_id))'

        # The body of demo/04_photoservice_transfer_01.ps1. That script cannot be called - it is a
        # "while (1)" loop with no way out - so its body is re-expressed here against Verify_ tables.
        # Everything it drives is the shipped function: Get-PgDataReader, Write-SqlTable and the two
        # Invoke-*Query, all inside the same pair of transactions.
        function Invoke-TransferPass {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $customerTargetId = Invoke-SqlQuery -Connection $sql -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.Verify_customer' -As SingleValue
            $orderTargetId = Invoke-SqlQuery -Connection $sql -Query 'SELECT ISNULL(MAX(id), 0) FROM dbo.Verify_order_header' -As SingleValue
            $orderTargetLastUpdated = Invoke-SqlQuery -Connection $sql -Query 'SELECT MAX(updated_at) FROM dbo.Verify_order_header' -As SingleValue

            $sourceTransaction = $pg.BeginTransaction([System.Data.IsolationLevel]::RepeatableRead)
            $targetTransaction = $sql.BeginTransaction()

            $dataReader = Get-PgDataReader -Connection $pg -Query 'SELECT id, firstname, surname, city, email, NOW() AS transfered_at FROM customer WHERE id > :id' -ParameterValues @{ id = $customerTargetId } -Transaction $sourceTransaction
            Write-SqlTable -Connection $sql -Table dbo.Verify_customer -DataReader $dataReader -Transaction $targetTransaction

            $dataReader = Get-PgDataReader -Connection $pg -Query 'SELECT * FROM order_header WHERE id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
            Write-SqlTable -Connection $sql -Table dbo.Verify_order_header -DataReader $dataReader -Transaction $targetTransaction

            $dataReader = Get-PgDataReader -Connection $pg -Query 'SELECT * FROM order_detail WHERE order_id > :target_id' -ParameterValues @{ target_id = $orderTargetId } -Transaction $sourceTransaction
            Write-SqlTable -Connection $sql -Table dbo.Verify_order_detail -DataReader $dataReader -Transaction $targetTransaction

            $updatedRows = Invoke-PgQuery -Connection $pg -Query 'SELECT * FROM order_header WHERE id <= :id AND updated_at > :updated_at' -ParameterValues @{ id = $orderTargetId ; updated_at = $orderTargetLastUpdated } -Transaction $sourceTransaction
            foreach ($row in $updatedRows) {
                Invoke-SqlQuery -Connection $sql -Query 'UPDATE dbo.Verify_order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{ updated_at = $row.updated_at ; payment_uuid = $row.payment_uuid ; shipment_uuid = $row.shipment_uuid ; id = $row.id } -Transaction $targetTransaction
            }

            $targetTransaction.Commit(); $targetTransaction.Dispose()
            $sourceTransaction.Commit(); $sourceTransaction.Dispose()
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds
        }

        try {
            $first = Invoke-TransferPass
            $second = Invoke-TransferPass
            $third = Invoke-TransferPass
            Write-VerifyLine "      transfer passes: first $first ms, second $second ms, third $third ms"

            # The shape, not the milliseconds. AGENTS.md records 3.5 s and 0.37 s, but both depend on
            # how long the shop has been running, so an absolute assertion would fail for a reason
            # that is not a defect.
            Test-Fact -Name 'the first pass carries the backlog and later passes are cheaper' -Ok ($second -lt $first -and $third -lt $first) -Detail "first $first ms vs $second / $third ms"

            $transferred = Invoke-SqlQuery -Connection $sql -Query 'SELECT COUNT(*) FROM dbo.Verify_order_header' -As SingleValue
            Test-Fact -Name 'the first pass moved the backlog it found' -Ok ($transferred -ge $sourceOrders) -Detail "$transferred order headers in SQL Server, $sourceOrders were in PostgreSQL when it started"

            # Values, not counts: every transferred order header compared column by column against
            # PostgreSQL, bounded to what the target actually holds because the shop keeps writing.
            $maxId = Invoke-SqlQuery -Connection $sql -Query 'SELECT MAX(id) FROM dbo.Verify_order_header' -As SingleValue
            $target = @(Invoke-SqlQuery -Connection $sql -Query "SELECT id, customer_id, created_at FROM dbo.Verify_order_header WHERE id <= $maxId ORDER BY id")
            $source = @(Invoke-PgQuery -Connection $pg -Query "SELECT id, customer_id, created_at FROM order_header WHERE id <= $maxId ORDER BY id")
            $differ = 0
            for ($i = 0; $i -lt [math]::Min($target.Count, $source.Count); $i++) {
                if ($target[$i].id -ne $source[$i].id -or
                    $target[$i].customer_id -ne $source[$i].customer_id -or
                    [datetime]$target[$i].created_at -ne [datetime]$source[$i].created_at) { $differ++ }
            }
            Test-Fact -Name 'order_header: 0 differences on id, customer_id and created_at' -Ok ($differ -eq 0 -and $target.Count -gt 0) -Detail "$differ of $($target.Count) differ"
        } finally {
            foreach ($table in 'dbo.Verify_customer', 'dbo.Verify_order_header', 'dbo.Verify_order_detail') {
                Invoke-SqlQuery -Connection $sql -Query "DROP TABLE IF EXISTS $table"
            }
        }
    }

    $sql.Close()
    $pg.Close()
} finally {
    Pop-Location
}

Complete-Verify
