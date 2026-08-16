# Reproduces the StackExchange numbers from AGENTS.md: Users.xml has 12220 rows, 12179 of them carry
# real milliseconds in LastAccessDate while all 12220 CreationDate values end in .000, and the import
# lands 0 of 12220 differing on either timestamp column on SQL Server, PostgreSQL and Oracle, with no
# tolerance.
#
# The asymmetry between the two columns is the point. CreationDate alone proves nothing - every value
# in it ends in .000, so a driver that silently discards milliseconds passes on that column and fails
# on the other. That is exactly how the worst defect of the port hid.
#
# Needs SQL Server, PostgreSQL and Oracle running. Uses the shipped Users and Badges tables rather
# than copies, because the DATETIME2(3) and TIMESTAMP(3) column types are part of what is being
# checked, and truncates them again at the end.
#
# Takes several minutes, mostly Oracle. Pass -ReportPath to watch it while it runs.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'StackExchange' -ReportPath $ReportPath

Push-Location -Path $PSScriptRoot/../demo
try {
    . ./init_stackexchange.ps1 *> $null
    $PSDefaultParameterValues = @{
        '*-Sql*:EnableException' = $true
        '*-Ora*:EnableException' = $true
        '*-Pg*:EnableException'  = $true
    }

    ##########################################################################
    # The source, before anything is compared against it
    ##########################################################################

    $usersPath = '../data/stackexchange/Users.xml'
    Test-Fact -Name 'Users.xml is on disk' -Ok (Test-Path -Path $usersPath) -Detail (Resolve-Path -Path $usersPath -ErrorAction Ignore)

    # Read independently of the import path - an XML parse rather than the line-by-line reader the
    # Import-*Table functions use, so the two cannot share a bug
    $xml = [xml](Get-Content -Path $usersPath -Raw)
    $sourceRows = @($xml.users.row)
    Test-Fact -Name 'Users.xml holds 12220 rows' -Ok ($sourceRows.Count -eq 12220) -Detail "$($sourceRows.Count) rows"

    $source = @{ }
    $creationWithMilliseconds = 0
    $lastAccessWithMilliseconds = 0
    foreach ($row in $sourceRows) {
        $creation = [datetime]::Parse($row.CreationDate, [cultureinfo]::InvariantCulture)
        $lastAccess = [datetime]::Parse($row.LastAccessDate, [cultureinfo]::InvariantCulture)
        $source[[int]$row.Id] = [PSCustomObject]@{ CreationDate = $creation ; LastAccessDate = $lastAccess }
        if ($creation.Millisecond -ne 0) { $creationWithMilliseconds++ }
        if ($lastAccess.Millisecond -ne 0) { $lastAccessWithMilliseconds++ }
    }

    Test-Fact -Name '12179 LastAccessDate values carry real milliseconds' -Ok ($lastAccessWithMilliseconds -eq 12179) -Detail "$lastAccessWithMilliseconds of $($sourceRows.Count)"
    Test-Fact -Name 'every CreationDate ends in .000, which is why that column alone proves nothing' -Ok ($creationWithMilliseconds -eq 0) -Detail "$creationWithMilliseconds of $($sourceRows.Count) carry milliseconds"

    ##########################################################################
    # Import into all three, and compare every value back against the file
    ##########################################################################

    $importParams = @{
        Path          = $usersPath
        TruncateTable = $true
        BatchSize     = 100
    }

    $providers = @(
        @{ Name = 'SQL Server' ; Table = 'dbo.Users' ; Query = 'SELECT Id, CreationDate, LastAccessDate FROM dbo.Users' }
        @{ Name = 'PostgreSQL' ; Table = 'Users' ; Query = 'SELECT Id, CreationDate, LastAccessDate FROM Users' }
        @{ Name = 'Oracle' ; Table = 'Users' ; Query = 'SELECT Id, CreationDate, LastAccessDate FROM Users' }
    )

    foreach ($provider in $providers) {
        Write-VerifyLine "      importing 12220 rows into $($provider.Name) ..."

        switch ($provider.Name) {
            'SQL Server' {
                Import-SqlTable -Connection $stackexchange.SqlConnection -Table $provider.Table @importParams
                $loaded = @(Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query $provider.Query)
            }
            'PostgreSQL' {
                Import-PgTable -Connection $stackexchange.PgConnection -Table $provider.Table @importParams
                $loaded = @(Invoke-PgQuery -Connection $stackexchange.PgConnection -Query $provider.Query)
            }
            'Oracle' {
                Import-OraTable -Connection $stackexchange.OraConnection -Table $provider.Table @importParams
                $loaded = @(Invoke-OraQuery -Connection $stackexchange.OraConnection -Query $provider.Query)
            }
        }

        Test-Fact -Name "$($provider.Name): 12220 rows land" -Ok ($loaded.Count -eq 12220) -Detail "$($loaded.Count) rows"

        # Property access is case-insensitive in PowerShell, which is the only reason one query text
        # works against all three - PostgreSQL folds the column names to lower case and Oracle to
        # upper. That is finding 6 of SIBLING-FINDINGS.md, and it is load-bearing here too.
        $creationDiffer = 0
        $lastAccessDiffer = 0
        $matched = 0
        $millisecondsSeen = 0
        foreach ($row in $loaded) {
            $expected = $source[[int]$row.Id]
            if (-not $expected) { continue }
            $matched++
            if ([datetime]$row.CreationDate -ne $expected.CreationDate) { $creationDiffer++ }
            if ([datetime]$row.LastAccessDate -ne $expected.LastAccessDate) { $lastAccessDiffer++ }
            if (([datetime]$row.LastAccessDate).Millisecond -ne 0) { $millisecondsSeen++ }
        }

        Test-Fact -Name "$($provider.Name): every row matched a row in the file" -Ok ($matched -eq 12220) -Detail "$matched of 12220"
        Test-Fact -Name "$($provider.Name): 0 of 12220 differ on CreationDate, no tolerance" -Ok ($creationDiffer -eq 0) -Detail "$creationDiffer differ"
        Test-Fact -Name "$($provider.Name): 0 of 12220 differ on LastAccessDate, no tolerance" -Ok ($lastAccessDiffer -eq 0) -Detail "$lastAccessDiffer differ"

        # The precondition that makes the line above mean anything. If the column had silently lost
        # its milliseconds on the way in, both sides of the comparison would still agree on
        # CreationDate - and this number would be 0 instead of 12179.
        Test-Fact -Name "$($provider.Name): the stored LastAccessDate still carries 12179 millisecond values" -Ok ($millisecondsSeen -eq 12179) -Detail "$millisecondsSeen of 12220"
    }

    ##########################################################################
    # Badges, which is the second file the demo imports
    ##########################################################################

    # Badges is here for -ColumnMap, which nothing else exercises. Badges.xml is the one file whose
    # timestamp attribute is called Date rather than CreationDate, while every table uses
    # CreationDate - so the import has to be told about the rename. Without the map it fails with
    # "Column 'CreationDate' does not allow DBNull.Value", which is what a forgotten mapping looks
    # like: not a wrong value, a missing one.
    $badgesPath = '../data/stackexchange/Badges.xml'
    $badgesXml = [xml](Get-Content -Path $badgesPath -Raw)
    $badgesRows = @($badgesXml.badges.row)
    Write-VerifyLine "      Badges.xml holds $($badgesRows.Count) rows"

    Test-Fact -Name 'Badges.xml really uses Date rather than CreationDate' `
        -Ok ($null -ne $badgesRows[0].Date -and $null -eq $badgesRows[0].CreationDate) -Detail "first row has Date=$($badgesRows[0].Date)"

    $badgesParams = @{
        Path          = $badgesPath
        TruncateTable = $true
        BatchSize     = 100
        ColumnMap     = @{ CreationDate = 'Date' }
    }
    Import-SqlTable -Connection $stackexchange.SqlConnection -Table dbo.Badges @badgesParams

    $badgesLoaded = @(Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'SELECT Id, CreationDate FROM dbo.Badges')
    Test-Fact -Name "Badges: all $($badgesRows.Count) rows of the file land in SQL Server" -Ok ($badgesLoaded.Count -eq $badgesRows.Count) -Detail "$($badgesLoaded.Count) rows"

    # The mapped column carries the file's Date values, not NULL and not something else. A row count
    # alone would pass with every CreationDate empty, which is the failure mode the map prevents.
    $badgesSource = @{ }
    foreach ($row in $badgesRows) { $badgesSource[[int]$row.Id] = [datetime]::Parse($row.Date, [cultureinfo]::InvariantCulture) }
    $badgesDiffer = 0
    $badgesNull = 0
    foreach ($row in $badgesLoaded) {
        if ($null -eq $row.CreationDate -or $row.CreationDate -is [DBNull]) { $badgesNull++ ; continue }
        if ([datetime]$row.CreationDate -ne $badgesSource[[int]$row.Id]) { $badgesDiffer++ }
    }
    Test-Fact -Name 'Badges: no CreationDate landed NULL' -Ok ($badgesNull -eq 0) -Detail "$badgesNull NULL"
    Test-Fact -Name 'Badges: -ColumnMap put the file Date into CreationDate, value for value' -Ok ($badgesDiffer -eq 0) -Detail "$badgesDiffer of $($badgesLoaded.Count) differ"

    # Only SQL Server here. The three-provider comparison is what the Users block above is for; this
    # block exists for the mapping, and that is provider-independent.
    #
    # No literal row count is asserted for Badges, because AGENTS.md records none and inventing one
    # would be a number copied out of a run rather than out of the data.

    ##########################################################################

    Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'TRUNCATE TABLE dbo.Users'
    Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'TRUNCATE TABLE dbo.Badges'
    Invoke-PgQuery -Connection $stackexchange.PgConnection -Query 'TRUNCATE TABLE Users'
    Invoke-OraQuery -Connection $stackexchange.OraConnection -Query 'TRUNCATE TABLE Users'

    $stackexchange.SqlConnection.Close()
    $stackexchange.PgConnection.Close()
    $stackexchange.OraConnection.Close()
} finally {
    Pop-Location
}

Complete-Verify
