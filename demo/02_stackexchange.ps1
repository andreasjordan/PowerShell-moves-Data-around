break
# This script needs PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_stackexchange.ps1

# Let's see what data we have
Get-ChildItem -Path ../data/stackexchange

$usersData = Get-Content -Path ../data/stackexchange/Users.xml
$usersData.Count
$usersData[0..3]
$usersData[-2,-1]

# The file content is valid XML
# But also all lines starting with "  <row" are valid XML
$line = $usersData[2]
$row = ([xml]$line).row
$row
$row.GetType()    # XmlElement
$row.Id.GetType() # String





################################
# Importing files to databases #
################################


# So we can read the file line by line
# Collect 1000 lines
# Send them to the database with a BULK INSERT
# Let the .NET part handle the type conversion
$importTableParams = @{
    Path          = '../data/stackexchange/Users.xml'
    TruncateTable = $true
    BatchSize     = 100
}
Import-SqlTable -Connection $stackexchange.SqlConnection -Table dbo.Users @importTableParams
Import-OraTable -Connection $stackexchange.OraConnection -Table Users @importTableParams
Import-PgTable -Connection $stackexchange.PgConnection -Table Users @importTableParams

Get-PSFMessage | Where-Object Message -like Finished*Milliseconds | Select-Object -Last 3

# We can also change the name of the columns with the ColumnMap parameter
$badgesData = Get-Content -Path ../data/stackexchange/Badges.xml
([xml]$badgesData[2]).row  # Only badges are created on "Date" instead of "CreationDate". But all tables use "CreationDate", so we need the mapping.

$importTableParams = @{
    Path          = '../data/stackexchange/Badges.xml'
    TruncateTable = $true
    BatchSize     = 100
    ColumnMap     = @{
        CreationDate = "Date"
    }
}
Import-SqlTable -Connection $stackexchange.SqlConnection -Table dbo.Badges @importTableParams
Import-OraTable -Connection $stackexchange.OraConnection -Table Badges @importTableParams
Import-PgTable -Connection $stackexchange.PgConnection -Table Badges @importTableParams

Get-PSFMessage | Where-Object Message -like Finished*Milliseconds | Select-Object -Last 3

# Just for information: There are also Export-*Table commands that can export data from tables to files with a json formated line per row.





####################################
# Streaming data between databases #
####################################


# Now let's start streaming. We will move the data from one database to another database. But we start with SQL Server only.

$connectParams = @{
    Instance   = $stackexchange.SqlInstance
    Credential = $stackexchange.SqlCredential
    Database   = $stackexchange.SqlDatabase
}
$sourceConnection = Connect-SqlInstance @connectParams
$targetConnection = Connect-SqlInstance @connectParams
$usersRowCount = Invoke-SqlQuery -Connection $sourceConnection -Query 'SELECT COUNT(*) FROM dbo.Users' -As SingleValue
$dataReader = Get-SqlDataReader -Connection $sourceConnection -Table dbo.Users 
$writeParams = @{
    Connection         = $targetConnection
    Table              = 'dbo.Import_Users'
    DataReader         = $dataReader
    DataReaderRowCount = $usersRowCount
    TruncateTable      = $true
    BatchSize          = 100
}
Write-SqlTable @writeParams



# But we can also stream from one database system to another database system.

$sourceConnection = Connect-PgInstance -Instance $stackexchange.PgInstance -Credential $stackexchange.PgCredential -Database $stackexchange.PgDatabase
$targetConnection = Connect-SqlInstance -Instance $stackexchange.SqlInstance -Credential $stackexchange.SqlCredential -Database $stackexchange.SqlDatabase
$usersRowCount = Invoke-PgQuery -Connection $sourceConnection -Query 'SELECT COUNT(*) FROM Users' -As SingleValue
$dataReader = Get-PgDataReader -Connection $sourceConnection -Table Users 
Write-SqlTable -Connection $targetConnection -Table dbo.Import_Users -DataReader $dataReader -DataReaderRowCount $usersRowCount -TruncateTable -BatchSize 100

$sourceConnection = Connect-OraInstance -Instance $stackexchange.OraInstance -Credential $stackexchange.OraCredential
$targetConnection = Connect-PgInstance -Instance $stackexchange.PgInstance -Credential $stackexchange.PgCredential -Database $stackexchange.PgDatabase
$usersRowCount = Invoke-OraQuery -Connection $sourceConnection -Query 'SELECT COUNT(*) FROM Users' -As SingleValue
$dataReader = Get-OraDataReader -Connection $sourceConnection -Table Users 
Write-PgTable -Connection $targetConnection -Table Import_Users -DataReader $dataReader -DataReaderRowCount $usersRowCount -TruncateTable -BatchSize 100

Get-PSFMessage | Where-Object Message -like Finished*Milliseconds | Select-Object -Last 3




###############################################
# Bonus: Streaming data to Azure SQL Database #
###############################################


# How to setup the Azure SQL Database will be published later...
$resourceGroupName = $env:AzureResourceGroupName
$serverName = $env:AzureServerName

$homeIP = (Invoke-WebRequest -Uri "http://ipinfo.io/json" -UseBasicParsing | ConvertFrom-Json).ip
$null = Set-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $serverName -Name AllowHome -StartIpAddress $homeIP -EndIpAddress $homeIP
$targetConnection = Connect-SqlInstance -Instance "$serverName.database.windows.net" -Credential $stackexchange.SqlCredential -Database $stackexchange.SqlDatabase


# Streaming from a file
#######################

$importTableParams = @{
    Connection    = $targetConnection
    Path          = '../data/stackexchange/Users.xml'
    Table         = 'dbo.Users'
    TruncateTable = $true
    BatchSize     = 100
}
Import-SqlTable @importTableParams


# Streaming from a database
###########################

$sourceConnection = Connect-SqlInstance -Instance $stackexchange.SqlInstance -Credential $stackexchange.SqlCredential -Database $stackexchange.SqlDatabase
$usersRowCount = Invoke-SqlQuery -Connection $sourceConnection -Query 'SELECT COUNT(*) FROM dbo.Users' -As SingleValue
$dataReader = Get-SqlDataReader -Connection $sourceConnection -Table dbo.Users 
$writeParams = @{
    Connection         = $targetConnection
    Table              = 'dbo.Import_Users'
    DataReader         = $dataReader
    DataReaderRowCount = $usersRowCount
    TruncateTable      = $true
    BatchSize          = 100
}
Write-SqlTable @writeParams





############################################
# Bonus: Importing data to NoSQL databases #
############################################


# PowerShell loves data as arrays of PSCustomObjects. So let's convert the XML data.

$usersData = Get-Content -Path ../data/stackexchange/Users.xml

$usersObjects = foreach ($line in $usersData) {
    # $line = $usersData[2]
    if ($line.Substring(0, 6) -eq '  <row') {
        $row = ([xml]$line).row
        # $row.GetType()    # XmlElement
        # $row.Id.GetType() # String
        [PSCustomObject]@{
            _id            = [int]$row.Id
            Reputation     = [int]$row.Reputation
            CreationDate   = [datetime]$row.CreationDate
            DisplayName    = $row.DisplayName
            LastAccessDate = [datetime]$row.LastAccessDate
            WebsiteUrl     = $row.WebsiteUrl
            Location       = $row.Location
            AboutMe        = $row.AboutMe
            Views          = [int]$row.Views
            UpVotes        = [int]$row.UpVotes
            DownVotes      = [int]$row.DownVotes
            AccountId      = [int]$row.AccountId
        }
    }
}

# Now we can upload the objects to a MongoDB collection.
Write-MdbCollection -Connection $stackexchange.MdbConnection -Collection Users -Data $usersObjects

# To prove the upload, let's get some users from Canada.
Read-MdbCollection -Connection $stackexchange.MdbConnection -Collection Users -Filter @{ Location = 'Canada' } -First 5 -Project @{ CreationDate = 1 ; DisplayName = 1 ; Location = 1}

# Or get all objects and fill a grid view.
Read-MdbCollection -Connection $stackexchange.MdbConnection -Collection Users | Out-GridView





##################################
# Bonus: Getting data from MinIO #
##################################


# MinIO is an Amazon S3 compatible storage that can easily be used with PowerShell

Get-MioFileList -Connection $stackexchange.MioConnection

$usersData = Get-MioFile -Connection $stackexchange.MioConnection -Key Users.xml
$usersData.Count





<####################################################################################################

Key takeaways:

* Files with a suitable format can be streamed to database tables.
* .NET can take care of type conversions.
* Streaming from one database to another database (system) is no problem.
* Data can also be uploaded to and retrieved from NoSQL databases.

####################################################################################################>





# Cleanup:
Remove-MdbCollection -Connection $stackexchange.MdbConnection -Collection Users
Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'TRUNCATE TABLE dbo.Users'
Invoke-OraQuery -Connection $stackexchange.OraConnection -Query 'TRUNCATE TABLE Users'
Invoke-PgQuery -Connection $stackexchange.PgConnection -Query 'TRUNCATE TABLE Users'
Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'TRUNCATE TABLE dbo.Badges'
Invoke-OraQuery -Connection $stackexchange.OraConnection -Query 'TRUNCATE TABLE Badges'
Invoke-PgQuery -Connection $stackexchange.PgConnection -Query 'TRUNCATE TABLE Badges'
Invoke-SqlQuery -Connection $stackexchange.SqlConnection -Query 'TRUNCATE TABLE dbo.Import_Users'
Invoke-OraQuery -Connection $stackexchange.OraConnection -Query 'TRUNCATE TABLE Import_Users'
Invoke-PgQuery -Connection $stackexchange.PgConnection -Query 'TRUNCATE TABLE Import_Users'
