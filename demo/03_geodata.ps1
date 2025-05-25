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


###################################
# Importing GPX data to databases #
###################################


# Let's transform the data to an array of objects
$data = Import-GpxFile -Path ../data/geodata/radrouten-berlin/*.gpx
$data | Format-Table

$data = Import-GpxFile -Path ../data/geodata/michael-mueller-verlag-berlin.gpx
$data | Format-Table

# $data = Import-GpxFile -Path C:\Users\AndreasJordan\Dropbox\ViewRanger_letzter_Export.gpx
# $data | ogv

Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'CREATE TABLE dbo.berlin_tours (type VARCHAR(10), name VARCHAR(250), geometry GEOMETRY)' 
# Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'TRUNCATE TABLE dbo.berlin_tours' 
# Invoke-SqlQuery -Connection $geodata.SqlConnection -Query 'DROP TABLE dbo.berlin_tours' 

foreach ($row in $data) {
    $invokeParams = @{
        Connection      = $geodata.SqlConnection
        Query           = 'INSERT INTO dbo.berlin_tours VALUES (@type, @name, geometry::STGeomFromText(@wkt, 4326).MakeValid())'
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
# SELECT * FROM dbo.berlin_tours WHERE type = 'Track'
# SELECT * FROM dbo.berlin_tours WHERE geometry.STNumPoints() > 5
# SELECT name, geometry.STAsText() AS wkt FROM dbo.berlin_tours WHERE type = 'Track'


# MORE DEMO CODE WILL BE PUBLISHED LATER...
