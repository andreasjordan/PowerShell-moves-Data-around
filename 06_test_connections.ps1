$ErrorActionPreference = 'Stop'

# This script is run twice by 01_setup.ps1: once inside WSL2 and once on Windows. The two runs do
# not prove the same thing - the one in WSL2 reaches the containers over the WSL2 loopback, while
# the one on Windows goes through the port forwarding, which is the only path a demo ever takes.

# Force IPv4 for localhost
$hostname = '127.0.0.1'

Import-Module PSFramework
Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path $PSScriptRoot/lib/*-*.ps1)) { . $file.FullName }
Write-PSFMessage -Level Host -Message 'Importing database libraries'
Import-OraLibrary
Import-PgLibrary
Import-KfkLibrary
$PSDefaultParameterValues = @{
    "*-Sql*:EnableException" = $true
    "*-Ora*:EnableException" = $true
    "*-Pg*:EnableException"  = $true
    "*-Mdb*:EnableException" = $true
    "*-Kfk*:EnableException" = $true
}

Write-PSFMessage -Level Host -Message 'Setting up variables and connections for Timesheets'
$timesheets = @{
    SqlInstance = $hostname
    SqlLogin    = 'TimeSheets'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'TimeSheets'
}
$timesheets.SqlCredential = [PSCredential]::new($timesheets.SqlLogin, ($timesheets.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$timesheets.SqlConnection = Connect-SqlInstance -Instance $timesheets.SqlInstance -Credential $timesheets.SqlCredential -Database $timesheets.SqlDatabase


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for StackExchange'
$stackexchange = @{
    SqlInstance = $hostname
    SqlLogin    = 'StackExchange'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'StackExchange'
    OraInstance = "$hostname/XEPDB1"
    OraUser     = 'stackexchange'
    OraPassword = 'Passw0rd!'
    PgInstance  = $hostname
    PgUser      = 'stackexchange'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'stackexchange'
    MdbInstance = $hostname
    MdbUser     = 'stackexchange'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'stackexchange'
}
$stackexchange.SqlCredential = [PSCredential]::new($stackexchange.SqlLogin, ($stackexchange.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.SqlConnection = Connect-SqlInstance -Instance $stackexchange.SqlInstance -Credential $stackexchange.SqlCredential -Database $stackexchange.SqlDatabase
$stackexchange.OraCredential = [PSCredential]::new($stackexchange.OraUser, ($stackexchange.OraPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.OraConnection = Connect-OraInstance -Instance $stackexchange.OraInstance -Credential $stackexchange.OraCredential
$stackexchange.PgCredential = [PSCredential]::new($stackexchange.PgUser, ($stackexchange.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.PgConnection = Connect-PgInstance -Instance $stackexchange.PgInstance -Credential $stackexchange.PgCredential -Database $stackexchange.PgDatabase
$stackexchange.MdbCredential = [PSCredential]::new($stackexchange.MdbUser, ($stackexchange.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))
$stackexchange.MdbConnection = Connect-MdbInstance -Instance $stackexchange.MdbInstance -Credential $stackexchange.MdbCredential -Database $stackexchange.MdbDatabase


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for Geodata'
$geodata = @{
    SqlInstance = $hostname
    SqlLogin    = 'Geodata'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'Geodata'
    PgInstance  = $hostname
    PgUser      = 'geodata'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'geodata'
    OraInstance = "$hostname/XEPDB1"
    OraUser     = 'geodata'
    OraPassword = 'Passw0rd!'
}
$geodata.SqlCredential = [PSCredential]::new($geodata.SqlLogin, ($geodata.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.SqlConnection = Connect-SqlInstance -Instance $geodata.SqlInstance -Credential $geodata.SqlCredential -Database $geodata.SqlDatabase
$geodata.PgCredential = [PSCredential]::new($geodata.PgUser, ($geodata.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.PgConnection = Connect-PgInstance -Instance $geodata.PgInstance -Credential $geodata.PgCredential -Database $geodata.PgDatabase
$geodata.OraCredential = [PSCredential]::new($geodata.OraUser, ($geodata.OraPassword | ConvertTo-SecureString -AsPlainText -Force))
$geodata.OraConnection = Connect-OraInstance -Instance $geodata.OraInstance -Credential $geodata.OraCredential


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for PhotoService'
$photoservice = @{
    SqlInstance = $hostname
    SqlLogin    = 'PhotoService'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'PhotoService'
    PgInstance  = $hostname
    PgUser      = 'photoservice'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'photoservice'
    MdbInstance = $hostname
    MdbUser     = 'photoservice'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'photoservice'
    # The port published to Windows. Inside WSL2 this run reaches the same broker over the WSL2
    # loopback, which is the published port too - only the application uses redpanda:9092.
    KfkInstance = "${hostname}:19092"
}
$photoservice.SqlCredential = [PSCredential]::new($photoservice.SqlLogin, ($photoservice.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.SqlConnection = Connect-SqlInstance -Instance $photoservice.SqlInstance -Credential $photoservice.SqlCredential -Database $photoservice.SqlDatabase
$photoservice.PgCredential = [PSCredential]::new($photoservice.PgUser, ($photoservice.PgPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.PgConnection = Connect-PgInstance -Instance $photoservice.PgInstance -Credential $photoservice.PgCredential -Database $photoservice.PgDatabase
$photoservice.MdbCredential = [PSCredential]::new($photoservice.MdbUser, ($photoservice.MdbPassword | ConvertTo-SecureString -AsPlainText -Force))
$photoservice.MdbConnection = Connect-MdbInstance -Instance $photoservice.MdbInstance -Credential $photoservice.MdbCredential -Database $photoservice.MdbDatabase
$photoservice.KfkProducer = Connect-KfkProducer -Instance $photoservice.KfkInstance
$photoservice.KfkProducer.Dispose()


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for ProjectStatus'
$projectstatus = @{
    SqlInstance = $hostname
    SqlLogin    = 'ProjectStatus'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'ProjectStatus'
}
$projectstatus.SqlCredential = [PSCredential]::new($projectstatus.SqlLogin, ($projectstatus.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$projectstatus.SqlConnection = Connect-SqlInstance -Instance $projectstatus.SqlInstance -Credential $projectstatus.SqlCredential -Database $projectstatus.SqlDatabase


Write-PSFMessage -Level Host -Message 'Finished'

Write-PSFMessage -Level Host -Message 'Redpanda Console: http://127.0.0.1:8080/topics'
Write-PSFMessage -Level Host -Message 'pgAdmin: http://127.0.0.1:5050/browser/'
