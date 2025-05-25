$ErrorActionPreference = 'Stop'

Import-Module PSFramework, ImportExcel
Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path $PSScriptRoot/lib/*-*.ps1)) { . $file.FullName }
$PSDefaultParameterValues = @{
    "*-Mio*:EnableException" = $true
}


# TimeSheets
# Excel files will be generated from sample.json
Write-PSFMessage -Level Host -Message 'Setting up Excel files for TimeSheets'
$timesheets = @{
    DataPath   = 'data/timesheets'
    SampleFile = 'sample.json'
}
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
# XML files will be uploaded to MinIO
Write-PSFMessage -Level Host -Message 'Setting up variables and connections for StackExchange'
$stackexchange = @{
    MioInstance = 'localhost'
    MioUser     = 'stackexchange'
    MioPassword = 'Passw0rd!'
    MioBucket   = 'stackexchange'
    Site        = 'dba.meta'
    DataPath    = 'data/stackexchange'
}
$stackexchange.MioCredential = [PSCredential]::new($stackexchange.MioUser, ($stackexchange.MioPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.MioConnection = Connect-MioInstance -Instance $stackexchange.MioInstance -Credential $stackexchange.MioCredential -Bucket $stackexchange.MioBucket
if (-not (Test-Path -Path $stackexchange.DataPath)) {
    $null = New-Item -Path $stackexchange.DataPath -ItemType Directory
    Write-PSFMessage -Level Host -Message 'Downloading StackExchange data'
    Push-Location -Path $stackexchange.DataPath
    Invoke-WebRequest -Uri "https://archive.org/download/stackexchange/$($stackexchange.Site).stackexchange.com.7z" -OutFile tmp.7z -UseBasicParsing
    $null = 7za e tmp.7z
    Remove-Item -Path tmp.7z
    Pop-Location
}
Write-PSFMessage -Level Host -Message 'Importing StackExchange data to MinIO'
$files = Get-ChildItem -Path $stackexchange.DataPath
foreach ($file in $files) {
    Set-MioFile -Connection $stackexchange.MioConnection -Key $file.Name -InFile $file.FullName
}


# Geodata
# GPX files will be downloaded from https://www.berlin.de/sen/uvk/mobilitaet-und-verkehr/verkehrsplanung/radverkehr/radverkehrsnetz/radrouten/gpx/
# GPX files will be downloaded from https://www.michael-mueller-verlag.de/de/reisefuehrer/deutschland/berlin-city/gps-daten/
# JSON file will be downloaded from datahub.io/core/geo-countries
$geodata = @{
    DataPath    = 'data/geodata'
}
if (-not (Test-Path -Path $geodata.DataPath)) {
    $null = New-Item -Path $geodata.DataPath -ItemType Directory
    Push-Location -Path $geodata.DataPath
    Write-PSFMessage -Level Host -Message 'Downloading GPX data from berlin.de'
    Invoke-WebRequest -Uri https://www.berlin.de/sen/uvk/_assets/verkehr/verkehrsplanung/radverkehr/radrouten/radrouten_komplett.7z -OutFile tmp.7z -UseBasicParsing
    $null = 7za x tmp.7z
    Start-Sleep -Seconds 2
    Remove-Item -Path tmp.7z
    Rename-Item -Path radrouten_komplett -NewName radrouten-berlin
    Write-PSFMessage -Level Host -Message 'Downloading GPX data from michael-mueller-verlag.de'
    Invoke-WebRequest -Uri https://mmv.me/52630/00.gpx -OutFile michael-mueller-verlag-berlin.gpx -UseBasicParsing
    Write-PSFMessage -Level Host -Message 'Downloading GeoJSON data from datahub.io'
    $geoJSON = Invoke-RestMethod -Method Get -Uri https://datahub.io/core/geo-countries/r/0.geojson
    # Optional: Just select all EU countries
    # $geoJSON.features = $geoJSON.features | Where-Object { $_.properties.'ISO3166-1-Alpha-3' -in 'AUT','BEL','BGR','HRV','CYP','CZE','DNK','EST','FIN','DEU','GRC','HUN','IRL','ITA','LVA','LTU','LUX','MLT','NLD','POL','PRT','ROU','SVK','SVN','ESP','SWE' -or $_.properties.name -in 'France'}
    $geoJSON | ConvertTo-Json -Depth 9 -Compress | Set-Content -Path countries.geojson
    Pop-Location
}

Write-PSFMessage -Level Host -Message 'Finished'
