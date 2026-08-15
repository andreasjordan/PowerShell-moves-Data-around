$ErrorActionPreference = 'Stop'

# Does Windows see the container ports?
#
# 01_setup.ps1 does not run this. It is here for the moment its last step fails, because a connection
# refused from Windows almost never means the database is down. 127.0.0.1:1521 is docker's published
# port inside WSL2, but on Windows it is a listener that wslrelay creates a moment after docker binds
# the port in the VM - and the relay does not publish every port at the same moment.
#
# Run it from a second PowerShell window while start_demo.ps1 sits in its WSL2 shell, or while
# 01_setup.ps1 is between its two connection tests.
#
# NO LISTENER means the forward is missing and the database is very probably fine - wait, or restart
# WSL2. If every port connects and a demo still cannot reach a database, then the network is fine and
# 06_test_connections.ps1 is the next thing to run: it asks the drivers instead of the sockets.
#
# The keys are strings on purpose: an [ordered] dictionary indexed with an int looks up the position
# rather than the key, so numeric keys silently return nothing.

$ports = [ordered]@{
    '1433'  = 'SQL Server'
    '1521'  = 'Oracle'
    '5432'  = 'PostgreSQL'
    '27017' = 'MongoDB'
    '19092' = 'Redpanda (Kafka)'
    '8080'  = 'Redpanda Console'
    '5050'  = 'pgAdmin'
}

$refused = 0

foreach ($key in $ports.Keys) {
    $port = [int]$key

    # Has wslrelay published this port on Windows at all?
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    $listener = if ($listeners) {
        $owner = (Get-Process -Id $listeners[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
        "listener on $($listeners[0].LocalAddress) ($owner)"
    } else {
        'NO LISTENER'
    }

    # And does a connection actually get through?
    $connected = Test-Connection -TargetName 127.0.0.1 -TcpPort $port -Quiet
    if (-not $connected) { $refused++ }

    "{0,-6} {1,-18} {2,-9} {3}" -f $port, $ports[$key], $(if ($connected) { 'CONNECT' } else { 'REFUSED' }), $listener
}

if ($refused -gt 0) {
    Write-Warning "$refused of $($ports.Count) ports cannot be reached from Windows"
    exit 1
}

"All $($ports.Count) ports are reachable from Windows."
exit 0
