# Reproduces the Geodata numbers from AGENTS.md: countries.geojson is 14643643 bytes with 258
# features, and PostGIS converts 258 of 258 with 0 invalid.
#
# The Oracle read-back is DELIBERATELY NOT ASSERTED. SDO_UTIL.TO_WKTGEOMETRY fails with ORA-13199 for
# a varying subset of the same 258 rows - seen at 31, 39, 40, 42 and 64 - and that non-determinism is
# documented with four rejected explanations in the sibling's DIFFERENCES.md. This script prints the
# count and asserts only that the import itself worked and that the failure is not total. Do not turn
# the printed number into an expected value.
#
# Needs SQL Server, PostgreSQL and Oracle running. Creates Verify_* tables and drops them again.
#
# Takes several minutes: 258 geometries into Oracle one at a time, and Canada alone is 1.5 MB of JSON.
# Pass -ReportPath to watch it while it runs.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'Geodata' -ReportPath $ReportPath

Push-Location -Path $PSScriptRoot/../demo
try {
    . ./init_geodata.ps1 *> $null
    . ./Import-GpxFile.ps1
    $PSDefaultParameterValues = @{
        '*-Sql*:EnableException' = $true
        '*-Ora*:EnableException' = $true
        '*-Pg*:EnableException'  = $true
    }

    ##########################################################################
    # GPX into SQL Server, through WKT
    ##########################################################################

    $tracks = @(Import-GpxFile -Path ../data/geodata/radrouten-berlin/*.gpx)
    Test-Fact -Name 'the Berlin GPX files parse into tracks' -Ok ($tracks.Count -gt 0) -Detail "$($tracks.Count) rows"

    # A track with an empty WKT would satisfy every count below without carrying any geometry
    $withWkt = @($tracks | Where-Object { $_.wkt -and $_.wkt.Length -gt 20 })
    Test-Fact -Name 'every parsed track carries a WKT string' -Ok ($withWkt.Count -eq $tracks.Count) -Detail "$($withWkt.Count) of $($tracks.Count)"

    Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'DROP TABLE IF EXISTS dbo.Verify_berlin_tours'
    Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'CREATE TABLE dbo.Verify_berlin_tours (type VARCHAR(10), name VARCHAR(250), geometry GEOMETRY)'
    try {
        foreach ($row in $tracks) {
            Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'INSERT INTO dbo.Verify_berlin_tours VALUES (@type, @name, geometry::STGeomFromText(@wkt, 4326).MakeValid())' -ParameterValues @{
                type = $row.type
                name = $row.name
                wkt  = $row.wkt
            }
        }

        $loaded = @(Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'SELECT name, geometry.STNumPoints() AS points FROM dbo.Verify_berlin_tours')
        Test-Fact -Name 'every track lands in SQL Server' -Ok ($loaded.Count -eq $tracks.Count) -Detail "$($loaded.Count) of $($tracks.Count) rows"

        $emptyGeometry = @($loaded | Where-Object { [int]$_.points -eq 0 })
        Test-Fact -Name 'no geometry landed empty' -Ok ($emptyGeometry.Count -eq 0) -Detail "$($emptyGeometry.Count) with 0 points"

        # Point counts against the source WKT, so that a geometry silently truncated on the way in
        # is caught. A row count would not notice it.
        $pointsDiffer = 0
        foreach ($row in $loaded) {
            $sourceWkt = ($tracks | Where-Object name -eq $row.name | Select-Object -First 1).wkt
            $sourcePoints = ([regex]::Matches($sourceWkt, ',')).Count + 1
            if ([int]$row.points -ne $sourcePoints) { $pointsDiffer++ }
        }
        Test-Fact -Name 'point counts match the source WKT' -Ok ($pointsDiffer -eq 0) -Detail "$pointsDiffer of $($loaded.Count) differ"
    } finally {
        Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'DROP TABLE IF EXISTS dbo.Verify_berlin_tours'
    }

    ##########################################################################
    # countries.geojson
    ##########################################################################

    $geoJsonPath = '../data/geodata/countries.geojson'
    $bytes = (Get-Item -Path $geoJsonPath).Length
    Test-Fact -Name 'countries.geojson is 14643643 bytes' -Ok ($bytes -eq 14643643) -Detail "$bytes bytes"

    $geoJSON = Get-Content -Path $geoJsonPath | ConvertFrom-Json
    $features = @($geoJSON.features)
    Test-Fact -Name 'countries.geojson holds 258 features, the whole world and not only the EU' -Ok ($features.Count -eq 258) -Detail "$($features.Count) features"

    ##########################################################################
    # PostGIS: 258 of 258, 0 invalid
    ##########################################################################

    Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE IF EXISTS Verify_countries'
    Invoke-PgQuery -Connection $geodata.PgConnection -Query 'CREATE TABLE Verify_countries (name VARCHAR(50), iso CHAR(3), geometry GEOMETRY)'
    try {
        $pgFailures = 0
        foreach ($feature in $features) {
            try {
                Invoke-PgQuery -Connection $geodata.PgConnection -Query 'INSERT INTO Verify_countries VALUES (:name, :iso, ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(:geometry), 4326)))' -ParameterValues @{
                    name     = $feature.properties.name
                    iso      = $feature.properties.'ISO3166-1-Alpha-3'
                    geometry = $feature.geometry | ConvertTo-Json -Depth 4 -Compress
                }
            } catch {
                $pgFailures++
                Write-VerifyLine "      PostGIS refused [$($feature.properties.name)]: $($_.Exception.Message -replace '\s+', ' ')"
            }
        }
        Test-Fact -Name 'PostGIS converts 258 of 258' -Ok ($pgFailures -eq 0) -Detail "$pgFailures failed"

        $pgRows = Invoke-PgQuery -Connection $geodata.PgConnection -Query 'SELECT COUNT(*) FROM Verify_countries' -As SingleValue
        Test-Fact -Name '258 rows in PostGIS' -Ok ($pgRows -eq 258) -Detail "$pgRows rows"

        $invalid = Invoke-PgQuery -Connection $geodata.PgConnection -Query 'SELECT COUNT(*) FROM Verify_countries WHERE NOT ST_IsValid(geometry)' -As SingleValue
        Test-Fact -Name '0 invalid geometries in PostGIS' -Ok ($invalid -eq 0) -Detail "$invalid invalid"

        # ST_IsValid is true for an empty geometry too, so without this the line above could pass
        # over 258 rows that hold nothing at all
        $empty = Invoke-PgQuery -Connection $geodata.PgConnection -Query 'SELECT COUNT(*) FROM Verify_countries WHERE ST_IsEmpty(geometry) OR ST_NPoints(geometry) = 0' -As SingleValue
        Test-Fact -Name 'no PostGIS geometry is empty' -Ok ($empty -eq 0) -Detail "$empty empty"
    } finally {
        Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE IF EXISTS Verify_countries'
    }

    ##########################################################################
    # Oracle: the import is deterministic, the read-back is not
    ##########################################################################

    # Oracle has no DROP TABLE IF EXISTS, and swallowing the exception with an empty catch would
    # also swallow a real failure - so the table is asked about first
    function Remove-OraTableIfPresent {
        $exists = Invoke-OraQuery -Connection $geodata.OraConnection -As SingleValue `
            -Query "SELECT COUNT(*) FROM user_tables WHERE table_name = 'VERIFY_COUNTRIES'"
        if ($exists) { Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE Verify_countries' }
    }

    Remove-OraTableIfPresent
    Invoke-OraQuery -Connection $geodata.OraConnection -Query 'CREATE TABLE Verify_countries (name VARCHAR2(50), iso CHAR(3), geometry SDO_GEOMETRY)'
    try {
        Write-VerifyLine '      importing 258 geometries into Oracle, one at a time - this is the slow part'
        $oraFailures = 0
        foreach ($feature in $features) {
            try {
                Invoke-OraQuery -Connection $geodata.OraConnection -Query 'INSERT INTO Verify_countries VALUES (:name, :iso, SDO_UTIL.FROM_GEOJSON(:geometry))' -ParameterValues @{
                    name     = $feature.properties.name
                    iso      = $feature.properties.'ISO3166-1-Alpha-3'
                    geometry = $feature.geometry | ConvertTo-Json -Depth 4 -Compress
                }
            } catch {
                $oraFailures++
                Write-VerifyLine "      Oracle refused [$($feature.properties.name)]: $($_.Exception.Message -replace '\s+', ' ')"
            }
        }
        Test-Fact -Name 'Oracle accepts 258 of 258 on the way in' -Ok ($oraFailures -eq 0) -Detail "$oraFailures failed"

        $oraRows = Invoke-OraQuery -Connection $geodata.OraConnection -Query 'SELECT COUNT(*) FROM Verify_countries' -As SingleValue
        Test-Fact -Name '258 rows in Oracle' -Ok ($oraRows -eq 258) -Detail "$oraRows rows"

        # The read-back, row by row, because one failing row aborts a whole-table SELECT and the
        # count is what we are after. The number below is INFORMATION, not an expectation.
        $wktFailures = 0
        $wktOk = 0
        $rowNumbers = @(Invoke-OraQuery -Connection $geodata.OraConnection -Query 'SELECT ROWNUM AS rn FROM Verify_countries')
        foreach ($rowNumber in $rowNumbers) {
            try {
                $null = Invoke-OraQuery -Connection $geodata.OraConnection -Query 'SELECT SDO_UTIL.TO_WKTGEOMETRY(geometry) AS wkt FROM (SELECT ROWNUM AS rn, geometry FROM Verify_countries) WHERE rn = :rn' -ParameterValues @{ rn = $rowNumber.rn } -As SingleValue
                $wktOk++
            } catch {
                $wktFailures++
            }
        }
        Write-VerifyLine "      Oracle TO_WKTGEOMETRY: $wktOk of 258 converted, $wktFailures failed with ORA-13199"
        Write-VerifyLine '      That count is non-deterministic on purpose - seen at 31, 39, 40, 42 and 64 over the'
        Write-VerifyLine '      same 258 rows. Do not turn it into an expected value; see DIFFERENCES.md.'

        Test-Fact -Name 'Oracle converts at least some geometries back to WKT' -Ok ($wktOk -gt 0) -Detail "$wktOk of 258 - a total failure would be a regression, a partial one is documented"
    } finally {
        Remove-OraTableIfPresent
    }

    $geodata.SqlConnection.Close()
    $geodata.PgConnection.Close()
    $geodata.OraConnection.Close()
} finally {
    Pop-Location
}

Complete-Verify
