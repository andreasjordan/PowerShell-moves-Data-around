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

Write-PSFMessage -Level Host -Message 'Setting up variables and connections for PhotoService'
$photoservice = @{
    SqlInstance = $localhost
    SqlLogin    = 'PhotoService'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'PhotoService'
    PgInstance  = $localhost
    PgUser      = 'photoservice'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'photoservice'
    MdbInstance = $localhost
    MdbUser     = 'photoservice'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'photoservice'
    MioInstance = $localhost
    MioUser     = 'photoservice'
    MioPassword = 'Passw0rd!'
    MioBucket   = 'photoservice'
}
$photoservice.SqlCredential = [PSCredential]::new($photoservice.SqlLogin, ($photoservice.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.SqlConnection = Connect-SqlInstance -Instance $photoservice.SqlInstance -Credential $photoservice.SqlCredential -Database $photoservice.SqlDatabase
$photoservice.PgCredential = [PSCredential]::new($photoservice.PgUser, ($photoservice.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.PgConnection = Connect-PgInstance -Instance $photoservice.PgInstance -Credential $photoservice.PgCredential -Database $photoservice.PgDatabase
$photoservice.MdbCredential = [PSCredential]::new($photoservice.MdbUser, ($photoservice.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.MdbConnection = Connect-MdbInstance -Instance $photoservice.MdbInstance -Credential $photoservice.MdbCredential -Database $photoservice.MdbDatabase
$photoservice.MioCredential = [PSCredential]::new($photoservice.MioUser, ($photoservice.MioPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.MioConnection = Connect-MioInstance -Instance $photoservice.MioInstance -Credential $photoservice.MioCredential -Bucket $photoservice.MioBucket

Write-PSFMessage -Level Host -Message 'Finished'
