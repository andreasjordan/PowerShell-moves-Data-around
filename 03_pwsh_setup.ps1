param (
    # AllUsers inside WSL2, so that the modules land in /usr/local/share/powershell/Modules and the
    # PhotoService container can mount them. CurrentUser on Windows, where AllUsers would need an
    # elevated shell and nothing mounts anything.
    [ValidateSet('AllUsers', 'CurrentUser')]
    [string]$Scope = 'AllUsers'
)

$ErrorActionPreference = 'Stop'

# This script runs twice: once inside WSL2 as root, and once on Windows. The demos are run from
# Windows, so a setup that only ever installed the modules in WSL2 could finish completely green
# while the machine that runs a demo had no ImportExcel at all.

if ((Get-PackageProvider).Name -notcontains 'NuGet') {
    # The same -Scope as the modules below, so that the Windows run does not need an elevated shell
    $null = Install-PackageProvider -Name Nuget -Scope $Scope -Force
}
if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# modules.txt is the one list. It used to be a literal array here and a prose list in README.md,
# which is two places to forget - the counterpart of requirements.txt in the sibling repository,
# where keeping two lists in step failed twice. Do not write the module names anywhere else.
$modules = Get-Content -Path $PSScriptRoot/modules.txt

$installedModules = (Get-Module -ListAvailable).Name
foreach ($module in $modules) {
    if ($installedModules -notcontains $module) {
        # Write-Host rather than Write-PSFMessage, because PSFramework is one of the modules this
        # loop is installing and may not exist yet
        Write-Host "Installing module $module with scope $Scope"
        Install-Module -Name $module -Scope $Scope
    }
}

Import-Module -Name PSFramework

# The ADO.NET drivers are downloaded into lib/ on first use. The repository is one directory on the
# Windows filesystem that WSL2 mounts, so the second run of this script finds the DLLs already
# there - but it still loads them, which is the check that this side can.
. $PSScriptRoot/lib/Import-OraLibrary.ps1
Import-OraLibrary

. $PSScriptRoot/lib/Import-PgLibrary.ps1
Import-PgLibrary
