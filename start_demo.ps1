$ErrorActionPreference = 'Stop'

# Start the demo environment
#
# 01_setup.ps1 builds everything and then stops the containers again, so this is what you run when
# you actually want to demo - after a reboot, or when switching to this repository from the sibling
# one. 04_docker_compose.sh stops the sibling's containers first if they are running, because both
# repositories publish the same ports.
#
# It keeps all data: the volumes survive, so every table a demo wrote last time is still there. One
# thing to expect in "docker compose logs sqlserver" afterwards is a page of "already exists" errors
# - its init script runs on every start and its CREATE statements are unconditional. Harmless.
wsl --cd $PSScriptRoot --user root ./04_docker_compose.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 04_docker_compose.sh'}

# The photoservice container restarts with the rest, which truncates its tables and restarts its
# schedule: the first order is ten minutes from now, the first payment fifteen, the first shipment
# twenty. The PhotoService demo is empty until then, and that looks broken when it is not.
Write-Warning 'demo 04 needs the photoservice application to have been running for twenty minutes'

# Run WSL2 to keep docker containers running
# If you exit this shell, WSL2 shuts down and takes the containers with it.
wsl --cd $PSScriptRoot --user root
