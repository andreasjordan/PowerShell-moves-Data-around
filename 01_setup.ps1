$ErrorActionPreference = 'Stop'

# Setup WSL2
wsl --cd $PSScriptRoot --user root ./02_wsl2_setup.sh
if ($LASTEXITCODE -ne 0) { throw 'failure in 02_wsl2_setup.sh'}

# Setup PowerShell
wsl --cd $PSScriptRoot --user root pwsh ./03_pwsh_setup.ps1
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

# Run WSL2 to keep docker containers running
wsl --cd $PSScriptRoot --user root
