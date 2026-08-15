$ErrorActionPreference = 'Stop'

# Install the PowerShell modules on Windows
# Everything else in this script happens inside WSL2, but the demos are run from here, so this is
# the side that has to be able to reach the databases in the end.
# It is first because it is the only step that costs nothing when it fails: a missing module or a
# PSGallery that cannot be reached is found in seconds, rather than after a quarter of an hour of
# Oracle starting up.
& $PSScriptRoot/03_pwsh_setup.ps1 -Scope CurrentUser

# Setup WSL2 with PowerShell, docker and 7-Zip
wsl --cd $PSScriptRoot --user root ./02_wsl2_setup.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 02_wsl2_setup.sh'}

# Install the PowerShell modules inside WSL2
wsl --cd $PSScriptRoot --user root pwsh ./03_pwsh_setup.ps1 -Scope AllUsers
if ($LASTEXITCODE -ne 0) { throw 'failure in 03_pwsh_setup.ps1'}

# Shutdown needed by docker
wsl --shutdown

# Start docker containers
wsl --cd $PSScriptRoot --user root ./04_docker_compose.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 04_docker_compose.sh'}

# Download sample data
wsl --cd $PSScriptRoot pwsh ./05_sample_data_setup.ps1
if ($LASTEXITCODE -ne 0) { throw 'failure in 05_sample_data_setup.ps1'}

# Test connections
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
$deadline = (Get-Date).AddMinutes(3)
foreach ($port in 1433, 1521, 5432, 27017, 19092) {
    while (-not (Test-Connection -TargetName 127.0.0.1 -TcpPort $port -Quiet)) {
        if ((Get-Date) -gt $deadline) {
            Write-Warning "no port forwarding on Windows for 127.0.0.1:$port"
            break
        }
        Start-Sleep -Seconds 5
    }
}

# Test connections from Windows
# The same script again, from the side that runs the demos.
#
# A failure here is remembered rather than thrown, so that the stop below still runs. Everything
# above this line has already been built, and there is no reason to leave the containers to be
# killed by the WSL2 idle timeout just because a connection test failed.
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
wsl --cd "$PSScriptRoot\docker" --user root docker compose stop
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'failure stopping the containers - they are still running and will be in the way of the sibling repository'
}

# The containers are down, so nothing needs WSL2 held open any more
Stop-Process -InputObject $keepWsl2Alive -ErrorAction Ignore

if ($windowsTestFailed) { throw 'failure in 06_test_connections.ps1 on Windows'}
