$ErrorActionPreference = 'Stop'

# Force IPv4 for localhost
$localhost = '127.0.0.1'

Import-Module PSFramework

Write-PSFMessage -Level Host -Message 'Importing PowerShell modules'
Import-Module ImportExcel, Microsoft.PowerShell.ConsoleGuiTools, Mdbc

Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path ../lib/*-*.ps1)) { . $file.FullName }

Write-PSFMessage -Level Host -Message 'Importing database libraries'
Import-OraLibrary
Import-PgLibrary

Write-PSFMessage -Level Host -Message 'Setting up variables and connections for StackExchange'
$stackexchange = @{
    SqlInstance = $localhost
    SqlLogin    = 'StackExchange'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'StackExchange'
    OraInstance = "$localhost/XEPDB1"
    OraUser     = 'stackexchange'
    OraPassword = 'Passw0rd!'
    PgInstance  = $localhost
    PgUser      = 'stackexchange'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'stackexchange'
    MdbInstance = $localhost
    MdbUser     = 'stackexchange'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'stackexchange'
    MioInstance = $localhost
    MioUser     = 'stackexchange'
    MioPassword = 'Passw0rd!'
    MioBucket   = 'stackexchange'
    Site        = 'dba.meta'
    DataPath    = '../data/stackexchange'
}
$stackexchange.SqlCredential = [PSCredential]::new($stackexchange.SqlLogin, ($stackexchange.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.SqlConnection = Connect-SqlInstance -Instance $stackexchange.SqlInstance -Credential $stackexchange.SqlCredential -Database $stackexchange.SqlDatabase
$stackexchange.OraCredential = [PSCredential]::new($stackexchange.OraUser, ($stackexchange.OraPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.OraConnection = Connect-OraInstance -Instance $stackexchange.OraInstance -Credential $stackexchange.OraCredential
$stackexchange.PgCredential = [PSCredential]::new($stackexchange.PgUser, ($stackexchange.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.PgConnection = Connect-PgInstance -Instance $stackexchange.PgInstance -Credential $stackexchange.PgCredential -Database $stackexchange.PgDatabase
$stackexchange.MdbCredential = [PSCredential]::new($stackexchange.MdbUser, ($stackexchange.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.MdbConnection = Connect-MdbInstance -Instance $stackexchange.MdbInstance -Credential $stackexchange.MdbCredential -Database $stackexchange.MdbDatabase
$stackexchange.MioCredential = [PSCredential]::new($stackexchange.MioUser, ($stackexchange.MioPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.MioConnection = Connect-MioInstance -Instance $stackexchange.MioInstance -Credential $stackexchange.MioCredential -Bucket $stackexchange.MioBucket

Write-PSFMessage -Level Host -Message 'Finished'
