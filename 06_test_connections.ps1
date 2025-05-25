$ErrorActionPreference = 'Stop'

Import-Module PSFramework
Write-PSFMessage -Level Host -Message 'Importing PowerShell functions'
foreach ($file in (Get-ChildItem -Path $PSScriptRoot/lib/*-*.ps1)) { . $file.FullName }
Write-PSFMessage -Level Host -Message 'Importing database libraries'
Import-OraLibrary
Import-PgLibrary
$PSDefaultParameterValues = @{
    "*-Sql*:EnableException" = $true
    "*-Ora*:EnableException" = $true
    "*-Pg*:EnableException"  = $true
    "*-Mdb*:EnableException" = $true
    "*-Mio*:EnableException" = $true
}

Write-PSFMessage -Level Host -Message 'Setting up variables and connections for Timesheets'
$timesheets = @{
    SqlInstance = 'localhost'
    SqlLogin    = 'TimeSheets'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'TimeSheets'
}
$timesheets.SqlCredential = [PSCredential]::new($timesheets.SqlLogin, ($timesheets.SqlPassword | ConvertTo-SecureString -AsPlainText -Force))
$timesheets.SqlConnection = Connect-SqlInstance -Instance $timesheets.SqlInstance -Credential $timesheets.SqlCredential -Database $timesheets.SqlDatabase


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for StackExchange'
$stackexchange = @{
    SqlInstance = 'localhost'
    SqlLogin    = 'StackExchange'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'StackExchange'
    OraInstance = 'localhost/XEPDB1'
    OraUser     = 'stackexchange'
    OraPassword = 'Passw0rd!'
    PgInstance  = 'localhost'
    PgUser      = 'stackexchange'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'stackexchange'
    MdbInstance = 'localhost'
    MdbUser     = 'stackexchange'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'stackexchange'
    MioInstance = 'localhost'
    MioUser     = 'stackexchange'
    MioPassword = 'Passw0rd!'
    MioBucket   = 'stackexchange'
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


Write-PSFMessage -Level Host -Message 'Setting up variables and connections for Geodata'
$geodata = @{
    SqlInstance = 'localhost'
    SqlLogin    = 'Geodata'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'Geodata'
    PgInstance  = 'localhost'
    PgUser      = 'geodata'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'geodata'
    OraInstance = 'localhost/XEPDB1'
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
    SqlInstance = 'localhost'
    SqlLogin    = 'PhotoService'
    SqlPassword = 'Passw0rd!'
    SqlDatabase = 'PhotoService'
    PgInstance  = 'localhost'
    PgUser      = 'photoservice'
    PgPassword  = 'Passw0rd!'
    PgDatabase  = 'photoservice'
    MdbInstance = 'localhost'
    MdbUser     = 'photoservice'
    MdbPassword = 'Passw0rd!'
    MdbDatabase = 'photoservice'
    MioInstance = 'localhost'
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

Write-PSFMessage -Level Host -Message 'MinIO: http://127.0.0.1:9001/login'
Write-PSFMessage -Level Host -Message 'pgAdmin: http://127.0.0.1:5050/browser/'
