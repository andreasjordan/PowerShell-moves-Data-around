break
# This script needs PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_geodata.ps1
. ./Import-GpxFile.ps1

# Let's see what data we have
Get-ChildItem -Path ../data/geodata
Get-ChildItem -Path ../data/geodata/radrouten-berlin

Get-Content -Path ../data/geodata/radrouten-berlin/europaradweg_r1_ost.gpx | Select-Object -First 20
Get-Content -Path ../data/geodata/radrouten-berlin/europaradweg_r1_ost.gpx | Select-Object -Last 10

Get-Content -Path ../data/geodata/michael-mueller-verlag-berlin.gpx | Select-Object -First 100
Get-Content -Path ../data/geodata/michael-mueller-verlag-berlin.gpx | Select-Object -Last 10





####################################
# Importing GPX data to a database #
####################################


# Let's transform the data to an array of objects
$data = Import-GpxFile -Path ../data/geodata/radrouten-berlin/*.gpx
$data | Format-Table

$data = Import-GpxFile -Path ../data/geodata/michael-mueller-verlag-berlin.gpx
$data | Format-Table

# $data = Import-GpxFile -Path C:\Users\AndreasJordan\Dropbox\ViewRanger_letzter_Export.gpx
# $data | ogv

$createQuery = 'CREATE TABLE dbo.berlin_tours (type VARCHAR(10), name VARCHAR(250), geometry GEOMETRY)' 
Invoke-SqlQuery -Connection $geodata.SqlConnection -Query $createQuery
# Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'TRUNCATE TABLE dbo.berlin_tours' 
# Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'DROP TABLE dbo.berlin_tours' 

$insertQuery = 'INSERT INTO dbo.berlin_tours VALUES (@type, @name, geometry::STGeomFromText(@wkt, 4326).MakeValid())'
foreach ($row in $data) {
    $invokeParams = @{
        Connection      = $geodata.SqlConnection
        Query           = $insertQuery
        ParameterValues = @{
            type = $row.type
            name = $row.name
            wkt  = $row.wkt
        }
    }
    try {
        Invoke-SqlQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import [$($row.name)]: $_"
        break
    }
}
# Some queries for the SQL Server Management Studio:
# SELECT * FROM dbo.berlin_tours WHERE type = 'Track'
# SELECT * FROM dbo.berlin_tours WHERE geometry.STNumPoints() > 5
# SELECT name, geometry.STAsText() AS wkt FROM dbo.berlin_tours WHERE type = 'Track'





######################################
# Transfer geodata between databases #
######################################


# Can we select the data? 
# Not directly ...
$sqlExport = Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'SELECT * FROM dbo.berlin_tours'  
# DataReader.GetFieldType(2) returned null.

# But we can convert the data back to WKT
$sqlExport = Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'SELECT type, name, geometry.STAsText() AS wkt FROM dbo.berlin_tours'
$sqlExport | Format-Table


# Let's create a table on PostgreSQL and fill it with the data
$createQuery = 'CREATE TABLE berlin_tours (type VARCHAR(10), name VARCHAR(250), geometry GEOMETRY)'
Invoke-PgQuery -Connection $geodata.PgConnection -Query $createQuery
# Invoke-PgQuery -Connection $geodata.PgConnection -Query 'TRUNCATE TABLE berlin_tours' 
# Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE berlin_tours' 

$insertQuery = 'INSERT INTO berlin_tours VALUES (:type, :name, ST_MakeValid(ST_GeomFromText(:wkt, 4326)))'
foreach ($row in $sqlExport) {
    $invokeParams = @{
        Connection      = $geodata.PgConnection
        Query           = $insertQuery
        ParameterValues = @{
            type = $row.type
            name = $row.name
            wkt  = $row.wkt
        }
    }
    try {
        Invoke-PgQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import [$($row.name)]: $_"
        break
    }
}
# Some queries for pgAdmin (http://127.0.0.1:5050/browser/):
# SELECT * FROM public.berlin_tours WHERE ST_NPoints(geometry) > 5
# SELECT * FROM public.berlin_tours WHERE type = 'Waypoint'


# Transfer the data to PostgreSQL with Write-PgTable
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'CREATE TABLE berlin_tours_import (type VARCHAR(10), name VARCHAR(250), wkt TEXT)' 
Write-PgTable -Connection $geodata.PgConnection -Table berlin_tours_import -Data $sqlExport
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'TRUNCATE TABLE berlin_tours' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'INSERT INTO berlin_tours SELECT type, name, ST_MakeValid(ST_GeomFromText(wkt, 4326)) FROM berlin_tours_import' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE berlin_tours_import' 





###########################
# Bonus: Import to Oracle #
###########################


$createQuery = 'CREATE TABLE berlin_tours (type VARCHAR2(10), name VARCHAR2(250), geometry SDO_GEOMETRY)'
Invoke-OraQuery -Connection $geodata.OraConnection -Query $createQuery

$insertQuery = 'INSERT INTO berlin_tours VALUES (:type, :name, SDO_UTIL.RECTIFY_GEOMETRY(SDO_GEOMETRY(:wkt, 4326), 0.01))'
foreach ($row in $sqlExport) {
    $invokeParams = @{
        Connection      = $geodata.OraConnection
        Query           = $insertQuery
        ParameterValues = @{
            type = $row.type
            name = $row.name
            wkt  = $row.wkt
        }
    }
    try {
        Invoke-OraQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import [$($row.name)]: $_"
        break
    }
}

Invoke-OraQuery -Connection $geodata.OraConnection -Query 'CREATE TABLE berlin_tours_import (type VARCHAR2(10), name VARCHAR2(250), wkt CLOB)' 
Write-OraTable -Connection $geodata.OraConnection -Table berlin_tours_import -Data $sqlExport
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'INSERT INTO berlin_tours SELECT type, name, SDO_UTIL.RECTIFY_GEOMETRY(SDO_GEOMETRY(wkt, 4326), 0.01) FROM berlin_tours_import' 
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE berlin_tours_import' 





############################
# Bonus: Import of GeoJSON #
############################


$geoJSON = Get-Content -Path ../data/geodata/countries.geojson | ConvertFrom-Json

$geoJSON | Format-List
$geoJSON.crs | Format-List  # CRS84 = WGS84 = EPSG:4326
$geoJSON.features.Count  # 27 - only the EU
$geoJSON.features[0] | Format-List
$geoJSON.features[0].properties | Format-List
$geoJSON.features[0].geometry | Format-List

# To import the data, we send the geometry data as a GeoJSON string to the database and use a function to convert it to the target datatype GEOMETRY.
# This only works on PostgreSQL and Oracle, as SQL Server can only process geometry data in the format WKT (well known text).

# Let's create the table and import the data to PostgreSQL
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'CREATE TABLE countries (name VARCHAR(50), iso CHAR(3), geometry GEOMETRY)'
foreach ($feature in $geoJSON.features) {
    $invokeParams = @{
        Connection      = $geodata.PgConnection
        Query           = 'INSERT INTO countries VALUES (:name, :iso, ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(:geometry), 4326)))'
        ParameterValues = @{
            name     = $feature.properties.name
            iso      = $feature.properties.'ISO3166-1-Alpha-3'
            geometry = $feature.geometry | ConvertTo-Json -Depth 4 -Compress 
        }
    }
    try {
        Invoke-PgQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import $($feature.properties.name): $_"
        break
    }
}

# Let's create the table and import the data to Oracle
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'CREATE TABLE countries (name VARCHAR(50), iso CHAR(3), geometry SDO_GEOMETRY)' 
foreach ($feature in $geoJSON.features) {
    $invokeParams = @{
        Connection      = $geodata.OraConnection
        Query           = 'INSERT INTO countries VALUES (:name, :iso, SDO_UTIL.FROM_GEOJSON(:geometry))'
        ParameterValues = @{
            name     = $feature.properties.name
            iso      = $feature.properties.'ISO3166-1-Alpha-3'
            geometry = $feature.geometry | ConvertTo-Json -Depth 4 -Compress
        }
    }
    try {
        Invoke-OraQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import $($feature.properties.name): $_"
        break
    }
}

# Failes with: ORA-13199: wk buffer merge failure
# https://stackoverflow.com/questions/70066764/wk-buffer-error-when-running-get-wkt-oracle-spatial-function-on-sdo-geometry-ob
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'SELECT name, iso, SDO_UTIL.TO_WKTGEOMETRY(geometry) AS wkt FROM countries'





################################
# Bonus: Import of Mauttabelle #
################################


$tmpMauttabelle = 'C:\tmp_mauttabelle'
if (-not (Test-Path -Path $tmpMauttabelle)) { $null = New-Item -Path $tmpMauttabelle -ItemType Directory }
$balmWebsite = Invoke-WebRequest -Uri https://www.balm.bund.de/DE/Themen/Lkw-Maut/Mauttabelle/mauttabelle_node.html -UseBasicParsing
$mauttabelleHref = ($balmWebsite.Links.href.Where({$_ -match 'zip'}) | Sort-Object)[-1]
$mauttabelleUri = "https://www.balm.bund.de/$mauttabelleHref"
Invoke-WebRequest -Uri $mauttabelleUri -OutFile "$tmpMauttabelle\mauttabelle.zip"
Expand-Archive -Path "$tmpMauttabelle\mauttabelle.zip" -DestinationPath $tmpMauttabelle
$mauttabelle = Import-Excel -Path "$tmpMauttabelle\*_Mauttabelle.xlsx" -StartRow 2
Remove-Item -Path $tmpMauttabelle -Recurse -Force

$mauttabelle.Count                         # 137.530
$mauttabelle[0].'Abschnitts-ID'.GetType()  # Double
$mauttabelle[0].'Länge'.GetType()          # Double
$mauttabelle[0].'Breite Von'.GetType()     # String

$mautDaten = foreach ($abschnitt in $mauttabelle) {
    [PSCustomObject]@{
        abschnitt   = [int]$abschnitt.'Abschnitts-ID'
        von         = $abschnitt.'Von'
        nach        = $abschnitt.'Nach'
        laenge      = [double]$abschnitt.'Länge'
        strasse     = $abschnitt.'Bundesfernstraße'
        bundesland  = $abschnitt.'Bundesland'
        breite_von  = [double]$abschnitt.'Breite Von'
        laenge_von  = [double]$abschnitt.'Länge Von'
        breite_nach = [double]$abschnitt.'Breite Nach'
        laenge_nach = [double]$abschnitt.'Länge Nach'
    }
}

Invoke-PgQuery -Connection $geodata.PgConnection -Query 'CREATE TABLE mauttabelle (abschnitt INT, von VARCHAR(100), nach VARCHAR(100), laenge NUMERIC(3,1), strasse VARCHAR(10), bundesland VARCHAR(10), breite_von NUMERIC(6,4), laenge_von NUMERIC(6,4), breite_nach NUMERIC(6,4), laenge_nach NUMERIC(6,4), geometry GEOMETRY, CONSTRAINT mauttabelle_pk PRIMARY KEY (abschnitt))'
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'CREATE TABLE mauttabelle_import (abschnitt INT, von VARCHAR(100), nach VARCHAR(100), laenge NUMERIC(3,1), strasse VARCHAR(10), bundesland VARCHAR(10), breite_von NUMERIC(6,4), laenge_von NUMERIC(6,4), breite_nach NUMERIC(6,4), laenge_nach NUMERIC(6,4))'
Write-PgTable -Connection $geodata.PgConnection -Table mauttabelle_import -Data $mautDaten
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'TRUNCATE TABLE mauttabelle' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'INSERT INTO mauttabelle SELECT abschnitt, von, nach, laenge, strasse, bundesland, breite_von, laenge_von, breite_nach, laenge_nach, ST_MakeLine(ST_Point(laenge_von, breite_von, 4326), ST_Point(laenge_nach, breite_nach, 4326)) FROM mauttabelle_import' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE mauttabelle_import' 

Invoke-OraQuery -Connection $geodata.OraConnection -Query 'CREATE TABLE mauttabelle (abschnitt INT, von VARCHAR2(100), nach VARCHAR2(100), laenge NUMERIC(3,1), strasse VARCHAR2(10), bundesland VARCHAR2(10), breite_von NUMERIC(6,4), laenge_von NUMERIC(6,4), breite_nach NUMERIC(6,4), laenge_nach NUMERIC(6,4), geometry SDO_GEOMETRY, CONSTRAINT mauttabelle_pk PRIMARY KEY (abschnitt))'
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'CREATE TABLE mauttabelle_import (abschnitt INT, von VARCHAR2(100), nach VARCHAR2(100), laenge NUMERIC(3,1), strasse VARCHAR2(10), bundesland VARCHAR2(10), breite_von NUMERIC(6,4), laenge_von NUMERIC(6,4), breite_nach NUMERIC(6,4), laenge_nach NUMERIC(6,4))'
Write-OraTable -Connection $geodata.OraConnection -Table mauttabelle_import -Data $mautDaten
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'TRUNCATE TABLE mauttabelle'
Invoke-OraQuery -Connection $geodata.OraConnection -Query "INSERT INTO mauttabelle SELECT abschnitt, von, nach, laenge, strasse, bundesland, breite_von, laenge_von, breite_nach, laenge_nach, SDO_GEOMETRY('LINESTRING (' || TO_CHAR(laenge_von, '90.0000') || ' ' || TO_CHAR(breite_von, '90.0000') || ', ' || TO_CHAR(laenge_nach, '90.0000') || ' ' || TO_CHAR(breite_nach, '90.0000') || ')', 4326) FROM mauttabelle_import"
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE mauttabelle_import' 





<####################################################################################################

Key takeaways:

* Most geodata formats can be converted into "well known text" (WKT) format.
* WKT strings can be converted into database specific datatypes inside of the VALUES clause.
* When selecting geodata from a table, we need to transform it back to WKT.
* Two steps for more performance: BulkCopy WKT into a staging table and convert with INSERT SELECT.

####################################################################################################>





# Cleanup:
Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'DROP TABLE dbo.berlin_tours'
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE berlin_tours' 
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE berlin_tours' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE countries' 
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE countries' 
Invoke-PgQuery -Connection $geodata.PgConnection -Query 'DROP TABLE mauttabelle' 
Invoke-OraQuery -Connection $geodata.OraConnection -Query 'DROP TABLE mauttabelle' 
