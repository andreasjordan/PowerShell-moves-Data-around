# Reproduces the Timesheets numbers from AGENTS.md: 94 rows from the three Department*.xlsx,
# 3 departments, 4 people.
#
# Needs SQL Server running. Creates dbo.Verify_Timesheet and drops it again.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'Timesheets' -ReportPath $ReportPath

# demo/ is the working directory the demos assume - Import-XlsTimesheet.ps1 lives there and the
# relative ../data and ../lib paths only resolve from it
Push-Location -Path $PSScriptRoot/../demo
try {
    Import-Module -Name PSFramework, ImportExcel
    foreach ($file in (Get-ChildItem -Path ../lib/*-Sql*.ps1)) { . $file.FullName }
    . ./Import-XlsTimesheet.ps1

    $PSDefaultParameterValues = @{ '*-Sql*:EnableException' = $true }

    # Preconditions on the source, before anything is compared against it
    $files = @(Get-ChildItem -Path ../data/timesheets/Department*.xlsx)
    Test-Fact -Name 'three Department*.xlsx on disk' -Ok ($files.Count -eq 3) -Detail "$($files.Count) files: $(($files.Name | Sort-Object) -join ', ')"

    # The shipped function, not a reimplementation of it - that is the point of driving lib/
    $excelData = @(Import-XlsTimesheet -Path ../data/timesheets/Department*.xlsx)

    $departments = @($excelData.Department | Sort-Object -Unique)
    $people = @($excelData.Person | Sort-Object -Unique)
    Test-Fact -Name '94 rows read from the three files' -Ok ($excelData.Count -eq 94) -Detail "$($excelData.Count) rows"
    Test-Fact -Name '3 departments' -Ok ($departments.Count -eq 3) -Detail ($departments -join ', ')
    Test-Fact -Name '4 people' -Ok ($people.Count -eq 4) -Detail ($people -join ', ')

    # Assert the rows carry real values before a comparison claims they match. A frame of 94 nulls
    # would satisfy every count above.
    $withStart = @($excelData | Where-Object { $_.Start -is [datetime] }).Count
    $ordered = @($excelData | Where-Object { $_.Start -is [datetime] -and $_.End -is [datetime] -and $_.Start -lt $_.End }).Count
    Test-Fact -Name 'every row has a [datetime] Start' -Ok ($withStart -eq 94) -Detail "$withStart of 94"
    Test-Fact -Name 'every row has End after Start' -Ok ($ordered -eq 94) -Detail "$ordered of 94"

    $credential = [PSCredential]::new('TimeSheets', ('Passw0rd!' | ConvertTo-SecureString -AsPlainText -Force))
    $connection = Connect-SqlInstance -Instance 127.0.0.1 -Credential $credential -Database TimeSheets

    # Our own table rather than the demo's dbo.Timesheet, so that a verify run cannot collide with
    # a demo somebody is stepping through
    Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE IF EXISTS dbo.Verify_Timesheet'
    Invoke-SqlQuery -Connection $connection -Query @'
CREATE TABLE dbo.Verify_Timesheet (
  Department VARCHAR(100),
  Person     VARCHAR(100),
  Start      DATETIME2,
  "End"      DATETIME2,
  Project    VARCHAR(100),
  Task       VARCHAR(1000),
  CONSTRAINT Verify_Timesheet_PK PRIMARY KEY (Department, Person, Start)
)
'@

    try {
        Write-SqlTable -Connection $connection -Table dbo.Verify_Timesheet -Data $excelData -TruncateTable

        $loaded = @(Invoke-SqlQuery -Connection $connection -Query 'SELECT Department, Person, Start, "End", Project, Task FROM dbo.Verify_Timesheet ORDER BY Department, Person, Start')
        Test-Fact -Name '94 rows land in SQL Server' -Ok ($loaded.Count -eq 94) -Detail "$($loaded.Count) rows"

        # Column by column against what was read from Excel, not a row count
        $source = @($excelData | Sort-Object Department, Person, Start)
        $differ = 0
        for ($i = 0; $i -lt [math]::Min($source.Count, $loaded.Count); $i++) {
            $a = $source[$i]; $b = $loaded[$i]
            if ($a.Department -ne $b.Department -or
                $a.Person -ne $b.Person -or
                [datetime]$a.Start -ne [datetime]$b.Start -or
                [datetime]$a.End -ne [datetime]$b.End -or
                $a.Project -ne $b.Project -or
                $a.Task -ne $b.Task) { $differ++ }
        }
        Test-Fact -Name '0 of 94 differ on any column' -Ok ($differ -eq 0) -Detail "$differ differ"

        # The minutes the demo's report is built from, so a silent type change in Start/End shows up
        $minutes = Invoke-SqlQuery -Connection $connection -Query 'SELECT SUM(DATEDIFF(minute, Start, "End")) FROM dbo.Verify_Timesheet' -As SingleValue
        $expected = [int](($excelData | ForEach-Object { ($_.End - $_.Start).TotalMinutes } | Measure-Object -Sum).Sum)
        Test-Fact -Name 'total minutes agree with the Excel data' -Ok ($minutes -eq $expected) -Detail "$minutes in SQL Server, $expected from Excel"
    } finally {
        Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE IF EXISTS dbo.Verify_Timesheet'
        $connection.Close()
    }
} finally {
    Pop-Location
}

Complete-Verify
