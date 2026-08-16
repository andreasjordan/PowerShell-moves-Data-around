$ErrorActionPreference = 'Stop'

# This script runs twice: once inside WSL2 as root, and once on Windows. The two runs do different
# amounts of work, and the guard below is the whole difference.
#
# Inside WSL2 it installs the modules and downloads the drivers. On Windows it only downloads the
# drivers, because the setup does not install anything on your machine - the modules there are
# yours, 00_check_host.ps1 has already confirmed they are present, and README.md says how to get
# them. See "The setup owns WSL2, not your machine" in AGENTS.md.

if (-not $IsWindows) {
    # AllUsers, so that the modules land in /usr/local/share/powershell/Modules and the
    # PhotoService container can mount them. There is no -Scope parameter any more: this branch
    # only ever runs inside WSL2, where AllUsers is the only scope that has ever been wanted.
    if ((Get-PackageProvider).Name -notcontains 'NuGet') {
        $null = Install-PackageProvider -Name Nuget -Scope AllUsers -Force
    }

    # Trusting the PSGallery is a change to the machine's configuration, and this is a throwaway
    # WSL2 installation that the setup owns. It is exactly the line that must not run on Windows.
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # modules.txt is the one list. It used to be a literal array here and a prose list in
    # README.md, which is two places to forget - the counterpart of requirements.txt in the sibling
    # repository, where keeping two lists in step failed twice. 00_check_host.ps1 reads this same
    # file to check the Windows side, so there is still nowhere else the names are written down.
    $installedModules = (Get-Module -ListAvailable).Name
    foreach ($module in (Get-Content -Path $PSScriptRoot/modules.txt)) {
        if ($installedModules -notcontains $module) {
            # Write-Host rather than Write-PSFMessage, because PSFramework is one of the modules
            # this loop is installing and may not exist yet
            Write-Host "Installing module $module with scope AllUsers"
            Install-Module -Name $module -Scope AllUsers
        }
    }
}

Import-Module -Name PSFramework

# The drivers are downloaded into lib/ here rather than on first use, and this script running twice
# is what makes that work. The repository is one directory on the Windows filesystem that WSL2
# mounts, so the second run mostly finds the files already there - but it still loads them, which is
# the check that this side can.
#
# This part runs on Windows too, and it is not a breach of the rule above: lib/ is inside the
# repository, not on your machine. Nothing here installs software, changes a policy or writes
# outside this directory - it fills a gitignored folder that the demos then load from. Doing it now
# also keeps a 40 MB download off the moment you open a demo in front of an audience.
#
# It also has to happen before 04_docker_compose.sh, and that is not a detail: the photoservice
# container mounts lib/ READ ONLY, so it can load a driver but can never download one. If these
# lines moved after the containers start, a fresh clone would give the application a directory with
# no drivers in it and no way to fix that itself.
. $PSScriptRoot/lib/Import-OraLibrary.ps1
Import-OraLibrary

. $PSScriptRoot/lib/Import-PgLibrary.ps1
Import-PgLibrary

# Kafka is the one driver that is not pure .NET, so this is also the step that puts the native
# librdkafka next to the managed assembly - a different file per platform, which is the other
# reason both runs of this script matter. Windows fetches librdkafka.dll and its OpenSSL, zlib and
# zstd companions; WSL2 fetches librdkafka.so, which the container then uses as well.
. $PSScriptRoot/lib/Import-KfkLibrary.ps1
Import-KfkLibrary
