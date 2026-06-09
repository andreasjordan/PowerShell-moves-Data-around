break
# This script works with both PowerShell 5.1 and PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# What demo data do we have?
Get-ChildItem -Path ..\data\projectstatus

# Let's open the Excel files and have a look at the data
& ..\data\projectstatus\ProjectStatus.xlsx





# Only once to install the module:
# Install-Module -Name ImportExcel -Scope CurrentUser
Import-Module -Name ImportExcel

$excelData = Import-Excel -Path ..\data\projectstatus\ProjectStatus.xlsx -WorksheetName ProjectStatus -StartRow 3 -DataOnly

# Let's see what we have imported
$excelData | Format-Table
$excelData | Out-GridView
$excelData[0] | Format-List





# So let's talk about the target data structure and create the table
####################################################################

# We need this table:
$createTableQuery = @'
CREATE TABLE dbo.ProjectStatus (
  Title            VARCHAR(50),
  Priority         VARCHAR(10),
  Manager          VARCHAR(50),
  Status           VARCHAR(50),
  Color            VARCHAR(10),
  ProgressPercent  INT,
  Milestone        VARCHAR(100),
  MilestoneDate    DATETIME2,
  CONSTRAINT ProjectStatus_PK 
  PRIMARY KEY (Title),
  CONSTRAINT ProjectStatus_Priority 
  CHECK (Priority IN ('Low', 'Medium', 'High')),
  CONSTRAINT ProjectStatus_Color 
  CHECK (Color IN ('Green', 'Yellow', 'Red')),
  CONSTRAINT ProjectStatus_ProgressPercent 
  CHECK (ProgressPercent >= 0 AND ProgressPercent <= 100)
)
'@

# To create the table, we need to connect to the database and execute the query

# The magic is hidden in some functions that we need to import
foreach ($file in (Get-ChildItem -Path ../lib/*-Sql*.ps1)) { . $file.FullName }

# We need to store the password inside of a PSCredential object
$credential = Get-Credential -Message 'Login to upload project status' -UserName ProjectStatus  # Password is: Passw0rd!

# Only if the password is "public":
# $credential = [PSCredential]::new('ProjectStatus', ('Passw0rd!' | ConvertTo-SecureString -AsPlainText -Force))

# Open the connection. I use my docker container and the localhost IP to force IPv4.
$connection = Connect-SqlInstance -Instance 127.0.0.1 -Credential $credential -Database ProjectStatus

# Now we can create the table
Invoke-SqlQuery -Connection $connection -Query $createTableQuery





# Let's try to upload the data to the database.
###############################################


# First we try to upload the data with Write-SqlTable

Write-SqlTable -Connection $connection -Table dbo.ProjectStatus -Data $excelData

# WARNING: [12:55:45][Write-SqlTable] Filling data table failed: The string 'Late july 2026' was not recognized as a valid DateTime. There is an unknown word starting at index '0'.Couldn't store <Late july 2026> in MilestoneDate Column.  Expected type is DateTime.

Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.ProjectStatus' | Format-Table

# No data was imported
# Only the first failed row is reported




# So we have to import the data row by row

# We will implement a function that imports a single row to have a clean code

function Import-ProjectStatusRow {
    param (
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][PSCustomObject]$Row,
        [switch]$EnableException
    )
    $invokeParams = @{
        Connection      = $Connection
        Query           = 'INSERT INTO dbo.ProjectStatus (Title, Priority, Manager, Status, Color, ProgressPercent, Milestone, MilestoneDate) ' +
                          'VALUES (@Title, @Priority, @Manager, @Status, @Color, @ProgressPercent, @Milestone, @MilestoneDate)'
        ParameterValues = @{
            Title           = $Row.Title
            Priority        = $Row.Priority
            Manager         = $Row.Manager
            Status          = $Row.Status
            Color           = $Row.Color
            ProgressPercent = $Row.ProgressPercent
            Milestone       = $Row.Milestone
            MilestoneDate   = $Row.MilestoneDate
        }
        EnableException = $EnableException
    }
    Invoke-SqlQuery @invokeParams
}


# We will skip empty rows and rows like "NEW PROJECTS:" that are used as section headers in the Excel file

Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.ProjectStatus'
foreach ($row in $excelData) {
    if ($row.Title -eq "") { continue }      # Skip empty rows
    if ($row.Title -match ':$') { continue } # Skip rows like "NEW PROJECTS:"
    Import-ProjectStatusRow -Connection $connection -Row $row
}
Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.ProjectStatus' | Format-Table

# 4 rows were imported, but 4 rows failed
# We see warnings, but the script continues to run and imports the valid rows. The invalid rows are not imported, but we don't know which ones they are.




# Now we enable exceptions in the function and catch them in the loop to identify the failed rows

Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.ProjectStatus'
foreach ($row in $excelData) {
    if ($row.Title -eq "") { continue }      # Skip empty rows
    if ($row.Title -match ':$') { continue } # Skip rows like "NEW PROJECTS:"
    try {
        Import-ProjectStatusRow -Connection $connection -Row $row -EnableException
        Write-Host "Imported row with Title '$($row.Title)' successfully."
    } catch {
        Write-Warning "Failed to import row with Title '$($row.Title)': $_"
    }
}
Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.ProjectStatus' | Format-Table

# We can identify the failed rows, but we still don't have a way to export them for further analysis. 




# Let's store the failed rows in a variable and export them to a new Excel file.

$excelData = Import-Excel -Path ..\data\projectstatus\ProjectStatus.xlsx -WorksheetName ProjectStatus -StartRow 3 -DataOnly
Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.ProjectStatus'
Remove-Item -Path ..\data\projectstatus\ProjectStatus_Failures.xlsx -ErrorAction Ignore
$failedRows = foreach ($row in $excelData) {
    if ($row.Title -eq "") { continue }      # Skip empty rows
    if ($row.Title -match ':$') { continue } # Skip rows like "NEW PROJECTS:"
    try {
        Import-ProjectStatusRow -Connection $connection -Row $row -EnableException
    }
    catch {
        # We add the error information to the row object and throw it to the pipeline to collect it in the $failedRows variable
        Add-Member -InputObject $row -MemberType NoteProperty -Name "ImportError" -Value $_
        $row
    }
}
Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.ProjectStatus' | Format-Table
$failedRows | Export-Excel -Path ..\data\projectstatus\ProjectStatus_Failures.xlsx -WorksheetName ImportFailures -BoldTopRow -AutoSize
& ..\data\projectstatus\ProjectStatus_Failures.xlsx




# We can also try to fix some of the failures.

$excelData = Import-Excel -Path ..\data\projectstatus\ProjectStatus.xlsx -WorksheetName ProjectStatus -StartRow 3 -DataOnly
Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.ProjectStatus'
Remove-Item -Path ..\data\projectstatus\ProjectStatus_Failures.xlsx -ErrorAction Ignore
$failedRows = foreach ($row in $excelData) {
    if ($row.Title -eq "") { continue }      # Skip empty rows
    if ($row.Title -match ':$') { continue } # Skip rows like "NEW PROJECTS:"
    try {
        Import-ProjectStatusRow -Connection $connection -Row $row -EnableException
    }
    catch {
        # The INSERT statement conflicted with the CHECK constraint "ProjectStatus_Color"
        if ($_.Exception.Message -match "ProjectStatus_Color") {
            Write-Warning "Failed to import row with Title '$($row.Title)' due to invalid color '$($row.Color)'. Setting color to 'Red' and trying again."
            $row.Color = 'Red'
            try {
                # We try to import the row again after fixing the color. If it fails again, we catch the exception and add the error information to the row object.
                Import-ProjectStatusRow -Connection $connection -Row $row -EnableException
                continue
            }
            catch {
                Write-Warning "Failed to import row with Title '$($row.Title)' even after fixing the color: $_"
            }
        }
        Add-Member -InputObject $row -MemberType NoteProperty -Name "ImportError" -Value $_
        $row
    }
}
Invoke-SqlQuery -Connection $connection -Query 'SELECT * FROM dbo.ProjectStatus' | Format-Table
$failedRows | Export-Excel -Path ..\data\projectstatus\ProjectStatus_Failures.xlsx -WorksheetName ImportFailures -BoldTopRow -AutoSize
& ..\data\projectstatus\ProjectStatus_Failures.xlsx

# We could also use AI to get the closest valid color based on the original value
# We could also use AI to parse the MilestoneDate column and convert values like "Late july 2026" to a valid date format.
# We could change 'unknown' values to NULL and allow NULLs in the database for those columns.
# We could also implement some basic fixes for the ProgressPercent column, like setting negative values to 0 and values greater than 100 to 100.





<####################################################################################################

Key takeaways:

* If data might be invalid, it's better to import it row by row and catch exceptions to identify failed rows.
* We can export failed rows for further analysis and fixing.
* We can implement some basic fixes in the import loop and try to import the fixed row again.
* We need to enable exceptions in the import function to be able to catch them in the loop.
* We get the original database error messages in the exceptions.

####################################################################################################>




# Cleanup:
Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE dbo.ProjectStatus' 
Remove-Item -Path ..\data\projectstatus\ProjectStatus_Failures.xlsx -ErrorAction Ignore
