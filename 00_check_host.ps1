# Checks that this machine has what the setup needs, and changes nothing at all.
#
# The setup owns WSL2 and this repository working tree. It does not install anything on your
# machine and it does not change your machine's configuration - see "The setup owns WSL2, not your
# machine" in AGENTS.md. Everything below is therefore yours to install, and this script exists so
# that a missing piece is named in seconds rather than found after a quarter of an hour of Oracle
# starting up.
#
# It has no dependencies, deliberately. It runs before anything is guaranteed to be there, so it
# imports no module and prints with Write-Host rather than the Write-PSFMessage the rest of the
# setup uses - PSFramework is one of the things it is checking for.
#
# 01_setup.ps1 runs it first and stops when it reports anything. It is read-only, so like
# 07_check_ports.ps1 it is also safe to run on its own at any time.

[CmdletBinding()]
param ()

# Deliberately not $ErrorActionPreference = 'Stop'. The point of this script is to name every
# missing piece in one pass; stopping at the first one means installing them one per run.

# The two helpers below are local to this script and do not follow the lib/ function contract -
# that contract is for lib/. A finding is what is missing plus the command that fixes it.
$missing = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param ([string]$What, [string]$Fix)
    $missing.Add([PSCustomObject]@{ What = $What ; Fix = $Fix })
}

function Write-Result {
    param ([string]$Name, [bool]$Ok, [string]$Detail)
    # 44 is the longest name below - "module Microsoft.PowerShell.ConsoleGuiTools"
    Write-Host ('  {0,-44} {1,-8} {2}' -f $Name, $(if ($Ok) { 'ok' } else { 'MISSING' }), $Detail)
}

Write-Host 'Checking this machine for what the setup needs'
Write-Host ''

# PowerShell itself
# 7.5 is what the demos ask for on their second line, and this script is already running on
# whatever is there, so the version is simply read rather than probed.
$powershellOk = $PSVersionTable.PSVersion -ge [version]'7.5'
Write-Result -Name 'PowerShell 7.5 or later' -Ok $powershellOk -Detail $PSVersionTable.PSVersion
if (-not $powershellOk) {
    Add-Finding -What "PowerShell $($PSVersionTable.PSVersion), but the demos need 7.5 or later" `
        -Fix 'winget install --id Microsoft.PowerShell --source winget'
}

# The modules
# modules.txt is the one list - 03_pwsh_setup.ps1 installs it inside WSL2 and this reads the same
# file, so there is still nowhere else the module names are written down.
$modulesMissing = @()
foreach ($module in (Get-Content -Path $PSScriptRoot/modules.txt)) {
    $found = [bool](Get-Module -Name $module -ListAvailable)
    Write-Result -Name "module $module" -Ok $found -Detail ''
    if (-not $found) { $modulesMissing += $module }
}
if ($modulesMissing) {
    Add-Finding -What "PowerShell modules not installed for you: $($modulesMissing -join ', ')" `
        -Fix "Install-Module -Name $($modulesMissing -join ', ') -Scope CurrentUser"
}

# WSL2
# Starting the default distribution is the check, rather than parsing "wsl --list --verbose" -
# that output is UTF-16LE on Windows and reading it is a well known trap. Asking Linux a question
# and reading its answer avoids the encoding question entirely, and it proves the thing that
# actually matters: that there is a default distribution and that it starts.
#
# It costs the few seconds of a cold WSL2 boot, which is why it says so first.
if (-not (Get-Command -Name wsl -ErrorAction SilentlyContinue)) {
    Write-Result -Name 'WSL2' -Ok $false -Detail 'no wsl command'
    Add-Finding -What 'WSL2 is not installed' `
        -Fix 'wsl --install -d Ubuntu-24.04   (in an elevated prompt, then reboot)'
} else {
    Write-Host '  starting the default WSL2 distribution to check it ...'
    $kernel = wsl -e uname -r 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $kernel) {
        Write-Result -Name 'a default WSL2 distribution' -Ok $false -Detail 'none that starts'
        Add-Finding -What 'WSL2 has no default distribution, or it does not start' `
            -Fix 'wsl --install -d Ubuntu-24.04   (in an elevated prompt, then reboot)'
    } else {
        # A WSL2 kernel names itself; a WSL1 one does not, and docker needs WSL2.
        $isWsl2 = $kernel -match 'WSL2'
        Write-Result -Name 'the distribution is WSL2' -Ok $isWsl2 -Detail $kernel
        if (-not $isWsl2) {
            Add-Finding -What "the default distribution runs on $kernel, which is not WSL2, and docker needs WSL2" `
                -Fix 'wsl --set-version <distribution> 2'
        }

        # 02_wsl2_setup.sh installs everything with apt and reads lsb_release, so a distribution
        # that is not Debian-based fails there in a way that says nothing about the cause.
        $null = wsl -e sh -c 'command -v apt-get' 2>$null
        $isApt = $LASTEXITCODE -eq 0
        Write-Result -Name 'the distribution has apt-get' -Ok $isApt -Detail ''
        if (-not $isApt) {
            Add-Finding -What 'the default distribution has no apt-get, and 02_wsl2_setup.sh installs everything with apt' `
                -Fix 'wsl --install -d Ubuntu-24.04   and make it the default with: wsl --set-default Ubuntu-24.04'
        }
    }
}

Write-Host ''

if (-not $missing.Count) {
    Write-Host 'This machine has everything the setup needs.'
    exit 0
}

Write-Host 'This machine is missing something the setup needs:'
Write-Host ''
foreach ($finding in $missing) {
    Write-Host "  * $($finding.What)"
    Write-Host "      $($finding.Fix)"
    Write-Host ''
}
Write-Host 'Install those yourself and run 01_setup.ps1 again. Nothing here has been changed.'
Write-Host 'Installing a module from the PSGallery may ask you to confirm that you trust it, which'
Write-Host 'is a decision the setup deliberately no longer makes on your behalf.'
exit 1
