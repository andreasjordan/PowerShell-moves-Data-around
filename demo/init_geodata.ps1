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

Write-PSFMessage -Level Host -Message 'Setting up variables and connections for Geodata'
$geodata = @{
    SqlInstance = $localhost
    SqlLogin    = 'Geodata'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'Geodata'
    PgInstance  = $localhost
    PgUser      = 'geodata'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'geodata'
    OraInstance = "$localhost/XEPDB1"
    OraUser     = 'geodata'
    OraPassword = 'Passw0rd!'
    Countries   = "../data/geodata/countries.geojson"
}
$geodata.SqlCredential = [PSCredential]::new($geodata.SqlLogin, ($geodata.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.SqlConnection = Connect-SqlInstance -Instance $geodata.SqlInstance -Credential $geodata.SqlCredential -Database $geodata.SqlDatabase
$geodata.PgCredential = [PSCredential]::new($geodata.PgUser, ($geodata.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.PgConnection = Connect-PgInstance -Instance $geodata.PgInstance -Credential $geodata.PgCredential -Database $geodata.PgDatabase
$geodata.OraCredential = [PSCredential]::new($geodata.OraUser, ($geodata.OraPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.OraConnection = Connect-OraInstance -Instance $geodata.OraInstance -Credential $geodata.OraCredential

Write-PSFMessage -Level Host -Message 'Finished'
