# Reproduces the event streaming checks behind entry 10 of SIBLING-FINDINGS.md: the five Kfk
# functions, the auto.offset.reset trap proved three ways, and a replay of the whole topic compared
# to PostgreSQL column by column.
#
# It also covers the two defects found on 2026-08-16, because both were invisible to every check
# that existed at the time: the topic must hold one application generation, and the timestamps on it
# must be whole milliseconds.
#
# Needs SQL Server, PostgreSQL, Redpanda and the photoservice container running.
#
# IT STOPS THE SHOP AND STARTS IT AGAIN. Freezing the source is the only way to compare a replay
# against PostgreSQL without the two moving apart underneath - and starting it again truncates its
# tables and empties the topic, so demos 4 and 6 need their usual two minutes afterwards.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'Event streaming' -ReportPath $ReportPath

$repositoryRoot = (Resolve-Path -Path $PSScriptRoot/..).Path

Push-Location -Path $PSScriptRoot/../demo
try {
    . ./init_photoservice.ps1 *> $null
    $PSDefaultParameterValues = @{
        '*-Sql*:EnableException' = $true
        '*-Pg*:EnableException'  = $true
        '*-Kfk*:EnableException' = $true
    }
    $sql = $photoservice.SqlConnection
    $pg = $photoservice.PgConnection

    ##########################################################################
    # The five Kfk functions, against a throwaway topic
    ##########################################################################

    $probeTopic = "verify.probe.$(Get-Random)"
    $producer = Connect-KfkProducer -Instance $photoservice.KfkInstance
    Test-Fact -Name 'Connect-KfkProducer returns a producer' -Ok ($null -ne $producer) -Detail $producer.GetType().Name

    $sent = 1..50 | ForEach-Object {
        [PSCustomObject]@{
            Seq    = $_
            Text   = "line $_ with a tab`t a newline`n and a backslash \ and Umlaute aeoeue"
            When   = [datetime]::SpecifyKind([datetime]::new(2026, 8, 16, 12, 34, 56, 789), 'Unspecified')
            Amount = [decimal]'9876.5432'
            Nested = [PSCustomObject]@{ Inner = [PSCustomObject]@{ Deep = "deep-$_" }; List = @(1, 2, 3) }
        }
    }
    Test-Fact -Name 'the probe payload really carries tab, newline and backslash' `
        -Ok (($sent[0].Text -match "`t") -and ($sent[0].Text -match "`n") -and ($sent[0].Text -match '\\')) -Detail 'present in the source'

    Write-KfkTopic -Connection $producer -Topic $probeTopic -Data $sent

    $groupA = "verify-a-$(Get-Random)"
    $consumerA = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId $groupA -FromBeginning
    $read = @(Read-KfkTopic -Connection $consumerA -Topic $probeTopic -First 50)
    Test-Fact -Name 'a new group with -FromBeginning reads all 50' -Ok ($read.Count -eq 50) -Detail "read $($read.Count)"

    $differ = 0
    for ($i = 0; $i -lt $read.Count; $i++) {
        $a = $sent[$i]; $b = $read[$i]
        if ($a.Seq -ne $b.Seq -or
            $a.Text -ne $b.Text -or
            $a.When -ne [datetime]$b.When -or
            $a.Amount -ne [decimal]$b.Amount -or
            $a.Nested.Inner.Deep -ne $b.Nested.Inner.Deep -or
            ($a.Nested.List -join ',') -ne ($b.Nested.List -join ',')) { $differ++ }
    }
    Test-Fact -Name 'the round trip is value-exact over all 50' -Ok ($differ -eq 0) -Detail "$differ of $($read.Count) differ"

    # The trap worth proving rather than describing: -FromBeginning is auto.offset.reset, which only
    # applies to a group that has never committed an offset.
    $consumerA.Close(); $consumerA.Dispose()
    $consumerAgain = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId $groupA -FromBeginning
    $reread = @(Read-KfkTopic -Connection $consumerAgain -Topic $probeTopic -Timeout 8)
    Test-Fact -Name 'the same group id reads 0 the second time' -Ok ($reread.Count -eq 0) -Detail "read $($reread.Count)"
    $consumerAgain.Close(); $consumerAgain.Dispose()

    $consumerB = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId "verify-b-$(Get-Random)" -FromBeginning
    $readAgain = @(Read-KfkTopic -Connection $consumerB -Topic $probeTopic -First 50)
    Test-Fact -Name 'a different group id reads all 50 again' -Ok ($readAgain.Count -eq 50) -Detail "read $($readAgain.Count)"
    $consumerB.Close(); $consumerB.Dispose()

    # Remove-KfkTopic, which is also how the probe topic is cleaned up. The topic list is read with
    # an admin client of our own rather than through lib/, because asking whether a thing is gone is
    # the one question the shipped function cannot answer about itself.
    Remove-KfkTopic -Instance $photoservice.KfkInstance -Topic $probeTopic

    $adminConfiguration = [System.Collections.Generic.Dictionary[string, string]]::new()
    $adminConfiguration['bootstrap.servers'] = $photoservice.KfkInstance
    $adminClient = [Confluent.Kafka.AdminClientBuilder]::new($adminConfiguration).Build()
    try {
        $stillThere = $adminClient.GetMetadata([timespan]::FromSeconds(10)).Topics.Topic -contains $probeTopic
    } finally {
        $adminClient.Dispose()
    }
    $producer.Dispose()
    Test-Fact -Name 'Remove-KfkTopic deleted the probe topic' -Ok (-not $stillThere) -Detail $probeTopic

    ##########################################################################
    # The real topic, with the shop frozen
    ##########################################################################

    Write-VerifyLine '      stopping the shop so that the topic and PostgreSQL stop moving apart'
    wsl --cd "$repositoryRoot/docker" --user root docker compose stop photoservice *> $null
    Start-Sleep -Seconds 3

    try {
        ######################################################################
        # The outbox, which is demo 6's first section
        ######################################################################

        # order_event and the order_header column it describes are written in one transaction, so
        # they agree in both directions. Two separately committed statements would agree too, most
        # of the time - the difference only shows on the row where the process died between them,
        # which is why the check runs with the shop stopped rather than mid-flight.
        $orphans = Invoke-PgQuery -Connection $pg -Query 'SELECT COUNT(*) FROM order_event WHERE order_id IS NULL' -As SingleValue
        Test-Fact -Name 'no order_event row has a NULL order_id' -Ok ($orphans -eq 0) -Detail "$orphans orphan(s)"

        foreach ($kind in 'payment', 'shipment') {
            $column = "${kind}_uuid"

            # Preconditions first. Both directions below are satisfied by an empty table, so without
            # this the two facts that follow would be green on a shop that had written nothing.
            $events = Invoke-PgQuery -Connection $pg -Query "SELECT COUNT(*) FROM order_event WHERE $column IS NOT NULL" -As SingleValue
            Test-Fact -Name "there are $kind rows in the outbox to check" -Ok ($events -gt 0) -Detail "$events rows"

            $eventWithoutChange = Invoke-PgQuery -Connection $pg -As SingleValue -Query @"
SELECT COUNT(*) FROM order_event e
WHERE e.$column IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM order_header h WHERE h.id = e.order_id AND h.$column = e.$column)
"@
            Test-Fact -Name "every $kind in the outbox has the matching order_header" -Ok ($eventWithoutChange -eq 0) -Detail "$eventWithoutChange without"

            $changeWithoutEvent = Invoke-PgQuery -Connection $pg -As SingleValue -Query @"
SELECT COUNT(*) FROM order_header h
WHERE h.$column IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM order_event e WHERE e.order_id = h.id AND e.$column = h.$column)
"@
            Test-Fact -Name "every $kind order_header has the matching outbox row" -Ok ($changeWithoutEvent -eq 0) -Detail "$changeWithoutEvent without"
        }

        ######################################################################
        # The topic
        ######################################################################

        $scan = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId "verify-scan-$(Get-Random)" -FromBeginning
        $partition = [Confluent.Kafka.TopicPartition]::new($photoservice.KfkTopic, 0)
        $watermark = $scan.QueryWatermarkOffsets($partition, [timespan]::FromSeconds(10))
        $total = $watermark.High.Value - $watermark.Low.Value
        Write-VerifyLine "      topic holds $total messages (low $($watermark.Low.Value), high $($watermark.High.Value))"

        Test-Fact -Name 'the topic is not empty' -Ok ($total -gt 0) -Detail "$total messages"
        $all = @(Read-KfkTopic -Connection $scan -Topic $photoservice.KfkTopic -First $total)
        Test-Fact -Name 'the whole topic reads up to the high watermark' -Ok ($all.Count -eq $total) -Detail "read $($all.Count) of $total"

        # One application generation. The shop restarts its ids at 1, so a topic that outlived the
        # tables holds one "Added customer" with id 1 per start - and the replay below then dies on
        # a primary key violation. This is the check that did not exist on 2026-08-16.
        $addedCustomer = @($all | Where-Object Message -eq 'Added customer')
        $idOne = @($addedCustomer | Where-Object { $_.Details.id -eq 1 })
        Test-Fact -Name 'the topic holds exactly one application generation' -Ok ($idOne.Count -eq 1) -Detail "$($idOne.Count) events with customer id = 1"
        $duplicates = ($addedCustomer | Group-Object { $_.Details.id } | Where-Object Count -gt 1).Count
        Test-Fact -Name 'no customer id appears twice on the topic' -Ok ($duplicates -eq 0) -Detail "$duplicates duplicated ids"

        # Whole milliseconds. TIMESTAMP(3) rounds, so anything finer makes the replay land a
        # different value in SQL Server than demo 4's direct transfer does.
        $headers = @($all | Where-Object Message -eq 'Added order header')
        if ($headers.Count) {
            $subMillisecond = @($headers | Where-Object { ([datetime]$_.Details.created_at).Ticks % [timespan]::TicksPerMillisecond -ne 0 })
            Test-Fact -Name 'every created_at on the topic is a whole number of milliseconds' -Ok ($subMillisecond.Count -eq 0) -Detail "$($subMillisecond.Count) of $($headers.Count) carry sub-millisecond digits"
        } else {
            Test-Fact -Name 'the topic has order headers to inspect' -Ok $false -Detail 'none - has the shop been up for a minute?'
        }

        ##########################################################################
        # The replay, compared to PostgreSQL column by column
        ##########################################################################

        foreach ($table in 'dbo.Verify_customer', 'dbo.Verify_order_header', 'dbo.Verify_order_detail') {
            Invoke-SqlQuery -Connection $sql -Query "DROP TABLE IF EXISTS $table"
        }
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_customer (id INT, firstname VARCHAR(50), surname VARCHAR(50), city VARCHAR(50), email VARCHAR(200), CONSTRAINT Verify_customer_pk PRIMARY KEY (id))'
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_order_header (id INT, customer_id INT, created_at DATETIME2, updated_at DATETIME2, payment_uuid UNIQUEIDENTIFIER, shipment_uuid UNIQUEIDENTIFIER, CONSTRAINT Verify_order_header_pk PRIMARY KEY (id))'
        Invoke-SqlQuery -Connection $sql -Query 'CREATE TABLE dbo.Verify_order_detail (order_id INT, photo_id INT, quantity INT, price NUMERIC(7, 2), CONSTRAINT Verify_order_detail_pk PRIMARY KEY (order_id, photo_id))'

        try {
            # demo 6's fold, unchanged apart from the table names
            $customers = [System.Collections.ArrayList]::new()
            $orderHeaders = [ordered]@{ }
            $lines = [System.Collections.ArrayList]::new()
            foreach ($loggingEvent in $all) {
                $details = $loggingEvent.Details
                switch ($loggingEvent.Message) {
                    'Added customer'      { $null = $customers.Add($details) }
                    'Added order header'  { $orderHeaders[[string]$details.id] = $details }
                    'Added order details' { $null = $lines.AddRange(@($details)) }
                    'Added payment'  { $h = $orderHeaders[[string]$details.OrderId]; if ($h) { $h.updated_at = $details.UpdatedAt; $h.payment_uuid = [guid]$details.PaymentUuid.Guid } }
                    'Added shipment' { $h = $orderHeaders[[string]$details.OrderId]; if ($h) { $h.updated_at = $details.UpdatedAt; $h.shipment_uuid = [guid]$details.ShipmentUuid.Guid } }
                }
            }

            $replayError = $null
            try {
                if ($customers.Count) { Write-SqlTable -Connection $sql -Table dbo.Verify_customer -Data $customers.ToArray() }
                if ($orderHeaders.Count) { Write-SqlTable -Connection $sql -Table dbo.Verify_order_header -Data @($orderHeaders.Values) }
                if ($lines.Count) { Write-SqlTable -Connection $sql -Table dbo.Verify_order_detail -Data $lines.ToArray() }
            } catch {
                $replayError = $_.Exception.Message
            }
            Test-Fact -Name 'the whole topic replays without a primary key violation' -Ok ($null -eq $replayError) -Detail $(if ($replayError) { $replayError } else { 'no error' })

            $sqlCustomers = @(Invoke-SqlQuery -Connection $sql -Query 'SELECT id, firstname, surname, city, email FROM dbo.Verify_customer ORDER BY id')
            $pgCustomers = @(Invoke-PgQuery -Connection $pg -Query 'SELECT id, firstname, surname, city, email FROM customer ORDER BY id')
            Test-Fact -Name 'customer row counts agree with PostgreSQL' -Ok ($sqlCustomers.Count -eq $pgCustomers.Count) -Detail "$($sqlCustomers.Count) replayed, $($pgCustomers.Count) in PostgreSQL"
            $differ = 0
            for ($i = 0; $i -lt [math]::Min($sqlCustomers.Count, $pgCustomers.Count); $i++) {
                $a = $sqlCustomers[$i]; $b = $pgCustomers[$i]
                if ($a.id -ne $b.id -or $a.firstname -ne $b.firstname -or $a.surname -ne $b.surname -or $a.city -ne $b.city -or $a.email -ne $b.email) { $differ++ }
            }
            Test-Fact -Name 'customer: 0 differences on every column' -Ok ($differ -eq 0 -and $sqlCustomers.Count -gt 0) -Detail "$differ of $($sqlCustomers.Count) differ"

            # NULL arrives as $null from one driver and [DBNull] from the other. A first version of
            # this comparison guarded only for [DBNull] and threw on the first NULL uuid.
            function AsDate { param($v) if ($null -eq $v -or $v -is [DBNull]) { $null } else { [datetime]$v } }
            function AsText { param($v) if ($null -eq $v -or $v -is [DBNull]) { $null } else { [string]$v } }

            $sqlHeaders = @(Invoke-SqlQuery -Connection $sql -Query 'SELECT id, customer_id, created_at, updated_at, payment_uuid, shipment_uuid FROM dbo.Verify_order_header ORDER BY id')
            $pgHeaders = @(Invoke-PgQuery -Connection $pg -Query 'SELECT id, customer_id, created_at, updated_at, payment_uuid, shipment_uuid FROM order_header ORDER BY id')
            Test-Fact -Name 'order_header row counts agree with PostgreSQL' -Ok ($sqlHeaders.Count -eq $pgHeaders.Count) -Detail "$($sqlHeaders.Count) replayed, $($pgHeaders.Count) in PostgreSQL"

            $columnDiffer = @{ id = 0; customer_id = 0; created_at = 0; updated_at = 0; payment_uuid = 0; shipment_uuid = 0 }
            $payCompared = 0; $shipCompared = 0; $updatedCompared = 0
            for ($i = 0; $i -lt [math]::Min($sqlHeaders.Count, $pgHeaders.Count); $i++) {
                $a = $sqlHeaders[$i]; $b = $pgHeaders[$i]
                if ($a.id -ne $b.id) { $columnDiffer.id++ }
                if ($a.customer_id -ne $b.customer_id) { $columnDiffer.customer_id++ }
                if ((AsDate $a.created_at) -ne (AsDate $b.created_at)) { $columnDiffer.created_at++ }
                if ((AsDate $a.updated_at) -ne (AsDate $b.updated_at)) { $columnDiffer.updated_at++ }
                if ($null -ne (AsDate $b.updated_at)) { $updatedCompared++ }
                if ((AsText $a.payment_uuid) -ne (AsText $b.payment_uuid)) { $columnDiffer.payment_uuid++ }
                if ($null -ne (AsText $b.payment_uuid)) { $payCompared++ }
                if ((AsText $a.shipment_uuid) -ne (AsText $b.shipment_uuid)) { $columnDiffer.shipment_uuid++ }
                if ($null -ne (AsText $b.shipment_uuid)) { $shipCompared++ }
            }
            foreach ($column in 'id', 'customer_id', 'created_at', 'updated_at', 'payment_uuid', 'shipment_uuid') {
                Test-Fact -Name "order_header $column`: 0 differences" -Ok ($columnDiffer[$column] -eq 0) -Detail "$($columnDiffer[$column]) of $($sqlHeaders.Count) differ"
            }

            # Without these the four uuid and timestamp comparisons above could all be NULL on both
            # sides and still read as green, which is how three checks passed for the wrong reason
            # in one session.
            Test-Fact -Name 'payment uuids were actually compared, so the fold did work' -Ok ($payCompared -gt 0) -Detail "$payCompared compared"
            Test-Fact -Name 'shipment uuids were actually compared, so the fold did work' -Ok ($shipCompared -gt 0) -Detail "$shipCompared compared"
            Test-Fact -Name 'updated_at was actually compared and is not all NULL' -Ok ($updatedCompared -gt 0) -Detail "$updatedCompared compared"

            $sqlLines = @(Invoke-SqlQuery -Connection $sql -Query 'SELECT order_id, photo_id, quantity, price FROM dbo.Verify_order_detail ORDER BY order_id, photo_id')
            $pgLines = @(Invoke-PgQuery -Connection $pg -Query 'SELECT order_id, photo_id, quantity, price FROM order_detail ORDER BY order_id, photo_id')
            Test-Fact -Name 'order_detail row counts agree with PostgreSQL' -Ok ($sqlLines.Count -eq $pgLines.Count) -Detail "$($sqlLines.Count) replayed, $($pgLines.Count) in PostgreSQL"
            $differ = 0
            for ($i = 0; $i -lt [math]::Min($sqlLines.Count, $pgLines.Count); $i++) {
                $a = $sqlLines[$i]; $b = $pgLines[$i]
                if ($a.order_id -ne $b.order_id -or $a.photo_id -ne $b.photo_id -or $a.quantity -ne $b.quantity -or [decimal]$a.price -ne [decimal]$b.price) { $differ++ }
            }
            Test-Fact -Name 'order_detail: 0 differences on every column' -Ok ($differ -eq 0 -and $sqlLines.Count -gt 0) -Detail "$differ of $($sqlLines.Count) differ"
        } finally {
            foreach ($table in 'dbo.Verify_customer', 'dbo.Verify_order_header', 'dbo.Verify_order_detail') {
                Invoke-SqlQuery -Connection $sql -Query "DROP TABLE IF EXISTS $table"
            }
        }

        $scan.Close(); $scan.Dispose()
    } finally {
        Write-VerifyLine '      starting the shop again - it truncates its tables and empties the topic'
        wsl --cd "$repositoryRoot/docker" --user root docker compose start photoservice *> $null
    }

    $sql.Close()
    $pg.Close()
} finally {
    Pop-Location
}

Complete-Verify
