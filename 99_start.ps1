$ErrorActionPreference = 'Stop'

# Start docker containers
wsl --cd $PSScriptRoot --user root ./04_docker_compose.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 04_docker_compose.sh'}

# Run WSL2 to keep docker containers running
wsl --cd $PSScriptRoot --user root
