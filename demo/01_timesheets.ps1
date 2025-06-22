break
# This script works with PowerShell 5.1

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# What demo data do we have?
Get-ChildItem -Path ..\data\timesheets

# Let's open the Excel files and have a look at the data
& ..\data\timesheets\DepartmentA.xlsx
& ..\data\timesheets\DepartmentB.xlsx
& ..\data\timesheets\DepartmentC.xlsx





# Only once to install the module:
# Install-Module -Name ImportExcel -Scope CurrentUser
Import-Module -Name ImportExcel

$excelData = Import-Excel -Path ..\data\timesheets\DepartmentA.xlsx -WorksheetName PersonA -StartRow 3 -AsDate date, time_from, time_to -DataOnly

# Let's see what we have imported
$excelData
$excelData.GetType().FullName          # We have an array of objects
$excelData[0].GetType().FullName       # The elements are of type PSCustomObject
$excelData[0].date.GetType().FullName  # The "date" is of type System.DateTime

# PowerShell can present us the data as a "table"
$excelData | Format-Table

# But we have more information:
# "Department" as the name of the file (yes, we can get a list of all Excel files in a directory)
# "Person" as the name of the worksheet (yes, we can get a list of all worksheets in an Excel file)

# And we have to calculate some data:
# Combine date and time_from / date and time_to





# So let's talk about the target data structure and create the table

# We need this table:
$createTableQuery = @'
CREATE TABLE dbo.Timesheet (
  Department VARCHAR(100),
  Person     VARCHAR(100),
  Start      DATETIME2,
  "End"      DATETIME2,
  Project    VARCHAR(100),
  Task       VARCHAR(1000),
  CONSTRAINT Timesheet_PK 
  PRIMARY KEY (
    Department,
    Person,
    Start
  )
)
'@

# To create the table, we need to connect to the database and execute the query

# The magic is hidden in some functions that we need to import
foreach ($file in (Get-ChildItem -Path ../lib/*-Sql*.ps1)) { . $file.FullName }

# We need to store the password inside of a PSCredential object
$credential = Get-Credential -Message 'Login to upload timesheets' -UserName TimeSheets  # Password is: Passw0rd!

# Only if the password is "public":
# $credential = [PSCredential]::new('TimeSheets', ('Passw0rd!' | ConvertTo-SecureString -AsPlainText -Force))

# Open the connection. I use my docker container and the localhost IP to force IPv4.
$connection = Connect-SqlInstance -Instance 127.0.0.1 -Credential $credential -Database TimeSheets

# Now we can create the table
Invoke-SqlQuery -Connection $connection -Query $createTableQuery





# Now we know what data we have and how the target table looks like
# Let's prepare the data (the "T" in "ETL")

# We start with only the first row
$row = $excelData[0]

$department = 'DepartmentA'
$person = 'PersonA'
$start = $row.date.AddHours($row.time_from.TimeOfDay.TotalHours)
$end = $row.date.AddHours($row.time_to.TimeOfDay.TotalHours)
$project = $row.project
$task = $row.task


# We start with a bad idea: Create the insert statement by concatenating strings
$insertQuery = "INSERT INTO dbo.Timesheet VALUES ('$department', '$person', '$start', '$end', '$project', '$task')"
$insertQuery 

# Does it work?
Invoke-SqlQuery -Connection $connection -Query $insertQuery

# Yes:
Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.Timesheet'

# Problems:
# * Exploits of a Mom (https://xkcd.com/327/)
# * Execution plans


# Better: Use bind variables

# First: truncate the table
Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.Timesheet'

# Change the query and create a hashtable with the parameter values
$insertQuery = "INSERT INTO dbo.Timesheet VALUES (@Department, @Person, @Start, @End, @Project, @Task)"
$insertParameters = @{
    Department = $department
    Person     = $person
    Start      = $start
    End        = $end
    Project    = $project
    Task       = $task
}

# Rund the query
Invoke-SqlQuery -Connection $connection -Query $insertQuery -ParameterValues $insertParameters

Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.Timesheet'


# Best: Use BULK INSERT

# The data needs to be an array of PSCustomObjects
$data = @( [PSCustomObject]$insertParameters )
Write-SqlTable -Connection $connection -Table dbo.Timesheet -Data $data -TruncateTable

Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.Timesheet'


# Now we can iterate over alle Excel files and iterate over all worksheets and iterate over all rows
# to generate an array of PSCustomObjects with all the data we want to import

# Let's just use another function I created:
. .\Import-XlsTimesheet.ps1
$excelData = Import-XlsTimesheet -Path ..\data\timesheets\Department*.xlsx
$excelData | Format-Table
$excelData | Out-GridView  # Does not work with PowerShell 7.5 as we can not use the filter

Write-SqlTable -Connection $connection -Table dbo.Timesheet -Data $excelData -TruncateTable

Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.Timesheet' | Format-Table





# Select data for a report and create Excel file

$projectQuery = 'SELECT Project, SUM(DATEDIFF(minute, Start, "End")) AS ProjectMinutesWorked FROM dbo.Timesheet GROUP BY Project'
$projectData = Invoke-SqlQuery -Connection $connection -Query $projectQuery
$projectData

$dateQuery = 'SELECT CAST(Start AS DATE) AS "Date", SUM(DATEDIFF(minute, Start, "End")) AS DateMinutesWorked FROM dbo.Timesheet GROUP BY CAST(Start AS DATE)'
$dateData = Invoke-SqlQuery -Connection $connection -Query $dateQuery
$dateData

$excelParams = @{
    Path          = '..\data\timesheets\Report.xlsx'
    WorksheetName = 'Report'
    AutoSize      = $true
    AutoNameRange = $true
    TableStyle    = 'Light18'
}

$projectDataParams = @{
    StartRow             = 20
    ExcelChartDefinition = @{
        ChartType      = 'Pie'
        Title          = 'Project'
        XRange         = 'Project'
        YRange         = 'ProjectMinutesWorked'
        LegendPosition = 'Bottom'
        Row            = 1
        Column         = 0
        Width          = 300
        Height         = 300
    }
}

$dateDataParams = @{
    StartRow             = 20
    StartColumn          = 5
    Style                = @{
        Range        = 'Date'
        NumberFormat = 'DD.MM.YYYY' 
    }
    ExcelChartDefinition = @{
        ChartType      = 'ColumnClustered'
        Title          = 'Date'
        XRange         = 'Date'
        YRange         = 'DateMinutesWorked'
        NoLegend       = $true
        Row            = 1
        Column         = 4
        Width          = 1000
        Height         = 300
    }
}

Remove-Item -Path $excelParams.Path -ErrorAction SilentlyContinue
$projectData | Export-Excel @excelParams @projectDataParams
$dateData | Export-Excel @excelParams @dateDataParams -Show


# Import the data from the report file (file needs to be closed)

Import-Excel -Path $excelParams.Path -StartColumn 1 -StartRow 20 -EndColumn 2 -DataOnly
Import-Excel -Path $excelParams.Path -StartColumn 5 -StartRow 20 -EndColumn 6 -AsDate Date





<####################################################################################################

Key takeaways:

* Excel is good at storing data including datatypes, better than CSV files.
* Inside of PowerShell data should be stored in arrays of PSCustomObjects.
* Inserts can use BULK INSERT with some databases like SQL Server and Oracle.
* If you need individual inserts, use bind parameters.
* PowerShell 5.1 can still be used.

####################################################################################################>




# Cleanup:
Remove-Item -Path $excelParams.Path -ErrorAction SilentlyContinue
Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE dbo.Timesheet'
