param (
    # The Excel files are rebuilt from sample.json every run, which costs a second. The downloads
    # are about 15 MB from three different sites, most of it countries.geojson, so they are skipped
    # when the files are already there. Use -Force to fetch them again.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Import-Module PSFramework
Import-Module ImportExcel 3>$null

# Nothing from lib/ is dot-sourced here any more. This script used to upload the StackExchange
# files to a MinIO bucket, which was the only reason it needed the data access layer at all;
# it creates and downloads sample data and touches no database.


# A helper for the four downloads below. It lives here rather than in lib/, so it does not follow
# the lib/ function contract: this is a setup script, and a failure here should stop it.
function Save-SampleFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Path
    )

    # Download to a temporary name and rename only once the whole file has arrived. A half written
    # countries.geojson otherwise stays behind looking like a perfectly good file and fails much
    # later, inside demo 03, as a JSON parse error that says nothing about a download.
    $partPath = "$Path.part"
    $response = Invoke-WebRequest -Uri $Uri -OutFile $partPath -UseBasicParsing -PassThru

    # A server that closes the connection early gives a short file and no error at all, so compare
    # what arrived against what was announced. A chunked response announces nothing, and then there
    # is nothing to compare against.
    $expectedLength = $response.Headers['Content-Length'] | Select-Object -First 1
    $length = (Get-Item -Path $partPath).Length
    if ($expectedLength -and $length -ne [int64]$expectedLength) {
        Remove-Item -Path $partPath
        throw "Download of $Uri is incomplete: got $length bytes, expected $expectedLength"
    }

    Move-Item -Path $partPath -Destination $Path -Force
}


# TimeSheets
# Excel files will be generated from sample.json
Write-PSFMessage -Level Host -Message 'Setting up Excel files for TimeSheets'
$timesheets = @{
    DataPath   = 'data/timesheets'
    SampleFile = 'sample.json'
}
Remove-item -Path "$($timesheets.DataPath)/*.xlsx" -ErrorAction Ignore
<# Code to generate sample data from Excel files
$files = Get-ChildItem -Path ./data/timesheets/*.xlsx
$data = foreach ($file in $files) {
    $sheets = Get-ExcelSheetInfo -Path $file.FullName
    foreach ($sheet in $sheets) {
        $rows = Import-Excel -Path $file.FullName -WorksheetName $sheet.Name -StartRow 3 -DataOnly
        foreach ($row in $rows) {
            [PSCustomObject]@{
                Department = $file.BaseName
                Person     = $sheet.Name
                Start      = $row.date.AddHours($row.time_from.TimeOfDay.TotalHours).ToString('yyyy-MM-ddTHH:mm:ss')
                End        = $row.date.AddHours($row.time_to.TimeOfDay.TotalHours).ToString('yyyy-MM-ddTHH:mm:ss')
                Project    = $row.project
                Task       = $row.task
            }
        }
    }
}
$data | ConvertTo-Json | Set-Content -Path "$($timesheets.DataPath)/$($timesheets.SampleFile)"
#>
$data = Get-Content -Path "$($timesheets.DataPath)/$($timesheets.SampleFile)" | ConvertFrom-Json
$departments = $data.Department | Sort-Object -Unique
foreach ($department in $departments) {
    # $department = $departments[0]
    $departmentData = $data | Where-Object Department -eq $department
    $persons = $departmentData.Person | Sort-Object -Unique
    foreach ($person in $persons) {
        # $person = $persons[0]
        $personData = $departmentData | Where-Object Person -eq $person
        $dataToExport = foreach ($row in $personData) {
            # $row = $personData[0]
            [PSCustomObject]@{
                date      = $row.Start.Date
                time_from = $row.Start.TimeOfDay
                time_to   = $row.End.TimeOfDay
                project   = $row.Project
                task      = $row.Task
            }
        }
        $excel = $dataToExport | Export-Excel -Path "$($timesheets.DataPath)/$department.xlsx" -WorksheetName $person -StartRow 3 -BoldTopRow -PassThru
        $worksheet = $excel.Workbook.Worksheets[$person]
        $worksheet.Column(1).Width = 12
        $worksheet.Column(1).Style.Numberformat.Format = 'dd.mm.yyyy'
        $worksheet.Cells['A3'].Style.HorizontalAlignment = 'right'
        $worksheet.Column(2).Width = 12
        $worksheet.Column(2).Style.Numberformat.Format = 'HH:mm'
        $worksheet.Cells['B3'].Style.HorizontalAlignment = 'right'
        $worksheet.Column(3).Width = 12
        $worksheet.Column(3).Style.Numberformat.Format = 'HH:mm'
        $worksheet.Cells['C3'].Style.HorizontalAlignment = 'right'
        $worksheet.Column(4).Width = 20
        $worksheet.Column(5).Width = 20
        $worksheet.Cells['A1'].Value = 'Please fill out this form weekly and send it to HR. Thanks!'
        $worksheet.Cells['A1'].Style.Font.Size = 14
        $worksheet.Cells['A1'].Style.Font.Bold = $true
        Close-ExcelPackage $excel
    }
}


# StackExchange
# XML files will be downloaded from archive.org/download/stackexchange
Write-PSFMessage -Level Host -Message 'Setting up variables for StackExchange'
$stackexchange = @{
    Site     = 'dba.meta'
    DataPath = 'data/stackexchange'
}

# "Are there any XML files" is a coarse check on purpose. It does not notice a half extracted
# archive, and should not try to - -Force is the answer to that, and a setup script that models
# partial states stops being readable.
$xmlFiles = @(Get-ChildItem -Path "$($stackexchange.DataPath)/*.xml" -ErrorAction Ignore)
if ($xmlFiles.Count -gt 0 -and -not $Force) {
    Write-PSFMessage -Level Host -Message "Keeping the $($xmlFiles.Count) StackExchange XML files that are already there"
} else {
    Write-PSFMessage -Level Host -Message 'Downloading StackExchange data'
    Remove-Item -Path "$($stackexchange.DataPath)/*.xml" -ErrorAction Ignore
    Push-Location -Path $stackexchange.DataPath
    Save-SampleFile -Uri "https://archive.org/download/stackexchange/$($stackexchange.Site).stackexchange.com.7z" -Path tmp.7z
    if ($IsLinux) {
        $null = 7za e -y tmp.7z
    } else {
        $null = C:\Progra~1\7-Zip\7z.exe e -y tmp.7z
    }
    Remove-Item -Path tmp.7z
    Pop-Location
}


# Geodata
# GPX files will be downloaded from https://www.berlin.de/sen/uvk/mobilitaet-und-verkehr/verkehrsplanung/radverkehr/radverkehrsnetz/radrouten/gpx/
# GPX files will be downloaded from https://www.michael-mueller-verlag.de/de/reisefuehrer/deutschland/berlin-city/gps-daten/
# JSON file will be downloaded from datahub.io/core/geo-countries
$geodata = @{
    DataPath    = 'data/geodata'
}
$geodata.RadroutenPath = "$($geodata.DataPath)/radrouten-berlin"
$geodata.SingleGpxPath = "$($geodata.DataPath)/michael-mueller-verlag-berlin.gpx"
$geodata.CountriesPath = "$($geodata.DataPath)/countries.geojson"

# The three artifacts come from three different sites and are checked one at a time, so deleting
# one of them does not fetch the other two again
$radrouten = @(Get-ChildItem -Path "$($geodata.RadroutenPath)/*.gpx" -ErrorAction Ignore)
if ($radrouten.Count -gt 0 -and -not $Force) {
    Write-PSFMessage -Level Host -Message "Keeping radrouten-berlin with $($radrouten.Count) GPX files"
} else {
    Write-PSFMessage -Level Host -Message 'Downloading GPX data from berlin.de'
    # Start from a clean directory, so a renamed file in the archive does not linger
    Remove-Item -Path $geodata.RadroutenPath -Recurse -ErrorAction Ignore
    $null = New-Item -Path $geodata.RadroutenPath -ItemType Directory
    Push-Location -Path $geodata.RadroutenPath
    Save-SampleFile -Uri https://www.berlin.de/sen/uvk/_assets/verkehr/verkehrsplanung/radverkehr/radrouten/radrouten_komplett.7z -Path tmp.7z
    if ($IsLinux) {
        $null = 7za x -y tmp.7z
    } else {
        $null = C:\Progra~1\7-Zip\7z.exe x -y tmp.7z
    }
    Start-Sleep -Seconds 2
    Remove-Item -Path tmp.7z
    Pop-Location
}

if ((Test-Path -Path $geodata.SingleGpxPath) -and -not $Force) {
    Write-PSFMessage -Level Host -Message "Keeping $(Split-Path -Path $geodata.SingleGpxPath -Leaf)"
} else {
    Write-PSFMessage -Level Host -Message 'Downloading GPX data from michael-mueller-verlag.de'
    Save-SampleFile -Uri https://mmv.me/52630/00.gpx -Path $geodata.SingleGpxPath
}

if ((Test-Path -Path $geodata.CountriesPath) -and -not $Force) {
    Write-PSFMessage -Level Host -Message "Keeping $(Split-Path -Path $geodata.CountriesPath -Leaf)"
} else {
    Write-PSFMessage -Level Host -Message 'Downloading GeoJSON data from datahub.io'
    # The whole world, 258 features and about 14 MB. It used to be read with Invoke-RestMethod and
    # written back out, so that the countries could optionally be reduced to the EU - but that
    # filter was commented out while demo/03_geodata.ps1 went on claiming 27 features. The largest
    # geometry is Canada at 1.5 MB of JSON, which is what makes the Oracle bind parameter in
    # Invoke-OraQuery interesting, so the full set is the better sample data.
    Save-SampleFile -Uri https://datahub.io/core/geo-countries/r/0.geojson -Path $geodata.CountriesPath
}


# ProjectStatus
# Excel files will be generated from sample.json
Write-PSFMessage -Level Host -Message 'Setting up Excel files for ProjectStatus'
$projectstatus = @{
    DataPath   = 'data/projectstatus'
    SampleFile = 'sample.json'
}
Remove-Item -Path "$($projectstatus.DataPath)/*.xlsx" -ErrorAction Ignore
$data = Get-Content -Path "$($projectstatus.DataPath)/$($projectstatus.SampleFile)" | ConvertFrom-Json
$excel = $data | Export-Excel -Path "$($projectstatus.DataPath)/ProjectStatus.xlsx" -WorksheetName ProjectStatus -StartRow 3 -BoldTopRow -PassThru
$worksheet = $excel.Workbook.Worksheets['ProjectStatus']
$worksheet.Column(1).Width = 25
$worksheet.Column(2).Width = 10
$worksheet.Column(3).Width = 15
$worksheet.Column(4).Width = 25
$worksheet.Column(5).Width = 10
$worksheet.Column(6).Width = 15
$worksheet.Column(6).Style.HorizontalAlignment = 'left'
$worksheet.Column(7).Width = 25
$worksheet.Column(8).Width = 15
$worksheet.Cells['A1'].Value = 'Please fill out this form weekly and send it to project management office. Thanks!'
$worksheet.Cells['A1'].Style.Font.Size = 14
$worksheet.Cells['A1'].Style.Font.Bold = $true
Close-ExcelPackage $excel

Write-PSFMessage -Level Host -Message 'Finished'
