$ErrorActionPreference = 'Stop'

# Every step announces itself before it runs, and the slow ones say how long they take.
#
# Two stretches of this script are quiet for minutes - 04_docker_compose.sh while Oracle creates
# its database, and the port wait near the end - and a quiet stretch with no output is
# indistinguishable from a script that has hung. Saying what is happening and roughly how long it
# takes is the whole fix.
#
# Write-Host rather than Write-PSFMessage, and this helper does not follow the lib/ function
# contract: the first step below is the one that checks whether PSFramework is installed at all.
function Write-Step {
    param ([string]$Message, [string]$Duration)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
    if ($Duration) { Write-Host "    $Duration" -ForegroundColor DarkGray }
}

# Check this machine
# The setup owns WSL2 and this repository, and nothing else - so the things this script cannot
# install are checked first and named all at once. It is also the only step that costs nothing when
# it fails: a missing module is found in seconds rather than after a quarter of an hour of Oracle
# starting up.
Write-Step -Message 'Checking this machine for what the setup needs' -Duration 'a few seconds, plus a WSL2 boot'
& $PSScriptRoot/00_check_host.ps1
if ($LASTEXITCODE -ne 0) { throw 'this machine is missing something the setup needs - see above' }

# Setup WSL2 with PowerShell, docker and 7-Zip
Write-Step -Message 'Installing PowerShell, docker and 7-Zip inside WSL2' -Duration 'several minutes on a fresh distribution'
wsl --cd $PSScriptRoot --user root ./02_wsl2_setup.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 02_wsl2_setup.sh'}

# Install the PowerShell modules inside WSL2, and the drivers into lib/
Write-Step -Message 'Installing the PowerShell modules inside WSL2 and downloading the drivers' -Duration 'a minute or two'
wsl --cd $PSScriptRoot --user root pwsh ./03_pwsh_setup.ps1
if ($LASTEXITCODE -ne 0) { throw 'failure in 03_pwsh_setup.ps1'}

# The same script on Windows, where it downloads the Windows drivers into lib/ and loads them
# It installs nothing on this machine - see the note at the top of 03_pwsh_setup.ps1. librdkafka
# comes as a different file per platform, so this run is what puts the Windows one next to the
# managed assembly, and loading it is the check that the demos will be able to.
Write-Step -Message 'Downloading the Windows drivers into lib/' -Duration 'under a minute, about 40 MB on a fresh clone'
& $PSScriptRoot/03_pwsh_setup.ps1

# Shutdown needed by docker
Write-Step -Message 'Shutting WSL2 down, which docker needs'
wsl --shutdown

# Start docker containers
Write-Step -Message 'Starting the containers and waiting for the demo databases' -Duration 'up to fifteen minutes the first time - Oracle is almost all of it'
wsl --cd $PSScriptRoot --user root ./04_docker_compose.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 04_docker_compose.sh'}

# Download sample data
Write-Step -Message 'Creating and downloading the sample data' -Duration 'seconds when it is already there, a few minutes on a fresh clone'
wsl --cd $PSScriptRoot pwsh ./05_sample_data_setup.ps1
if ($LASTEXITCODE -ne 0) { throw 'failure in 05_sample_data_setup.ps1'}

# Test connections
Write-Step -Message 'Testing every connection from inside WSL2'
wsl --cd $PSScriptRoot pwsh ./06_test_connections.ps1
if ($LASTEXITCODE -ne 0) { throw 'failure in 06_test_connections.ps1'}

# Hold WSL2 open for the rest of the script
# Everything from here on runs on Windows, so no "wsl" process is alive - and WSL2 terminates the
# distribution a few seconds after its last process exits, taking every container with it. That is
# the same reason start_demo.ps1 ends in a "wsl" shell.
#
# Measured before this existed: the last WSL2 step finished at 20:56:01, and at 20:56:16 every
# container logged a shutdown - postgres "received fast shutdown request", mongo a SignalHandler.
# The connection test two seconds later then failed against a database that no longer existed, with
# a socket error that reads exactly like a missing port forward. It is not one.
$keepWsl2Alive = Start-Process -FilePath wsl -ArgumentList 'sleep', '900' -PassThru -NoNewWindow

# Wait for the port forwarding on the Windows side
# The step above reaches the containers over the WSL2 loopback. Windows reaches them through
# wslrelay, which publishes each container port here a moment after docker binds it inside WSL2 -
# and those moments are not the same for every port. Connecting is cheap and silent, so wait for
# the forward rather than letting that race decide whether the setup succeeded.
Write-Step -Message 'Waiting for the Windows port forwarding' -Duration 'instant when the forwards are up, minutes on a cold install'
$deadline = (Get-Date).AddMinutes(3)
foreach ($port in 1433, 1521, 5432, 27017, 19092) {
    # Named one at a time, because this wait used to be completely silent and a port that lags the
    # others by minutes then looks exactly like a hung script
    Write-Host -NoNewline "    127.0.0.1:$port ... "
    while (-not (Test-Connection -TargetName 127.0.0.1 -TcpPort $port -Quiet)) {
        if ((Get-Date) -gt $deadline) {
            Write-Host 'not forwarded'
            Write-Warning "no port forwarding on Windows for 127.0.0.1:$port"
            break
        }
        Start-Sleep -Seconds 5
    }
    if ((Get-Date) -le $deadline) { Write-Host 'ok' }
}

# Test connections from Windows
# The same script again, from the side that runs the demos.
#
# A failure here is remembered rather than thrown, so that the stop below still runs. Everything
# above this line has already been built, and there is no reason to leave the containers to be
# killed by the WSL2 idle timeout just because a connection test failed.
Write-Step -Message 'Testing every connection from Windows, which is where the demos run'
pwsh -File "$PSScriptRoot\06_test_connections.ps1"
$windowsTestFailed = $LASTEXITCODE -ne 0
if ($windowsTestFailed) {
    Write-Warning 'failure in 06_test_connections.ps1 on Windows - run start_demo.ps1 and then 07_check_ports.ps1 to look into it'
}

# Stop the containers again
# This script sets the machine up, it does not start a demo. The volumes exist now - Oracle's first
# start is most of the time this script takes - so from here on, starting the containers is a minute
# rather than a quarter of an hour. start_demo.ps1 is what you run when you want to demo.
#
# Stopping here is what lets this script be run for both repositories one after the other: the
# sibling's setup would otherwise find these containers holding every port it wants.
#
# And it is a stop, not an exit: without it the containers are not left running, they are killed
# when WSL2 idles out, and SQL Server and Oracle do crash recovery on the next start.
Write-Step -Message 'Stopping the containers again - the setup builds, start_demo.ps1 runs' -Duration 'about a minute'
wsl --cd "$PSScriptRoot\docker" --user root docker compose stop
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'failure stopping the containers - they are still running and will be in the way of the sibling repository'
}

# The containers are down, so nothing needs WSL2 held open any more
Stop-Process -InputObject $keepWsl2Alive -ErrorAction Ignore

if ($windowsTestFailed) { throw 'failure in 06_test_connections.ps1 on Windows'}

Write-Step -Message 'Finished. Run start_demo.ps1 when you want to demo.'
