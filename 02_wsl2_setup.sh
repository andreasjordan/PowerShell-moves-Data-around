#!/bin/bash

# Stop on the first error. The blocks below used to be one long "&& \" chain, which meant
# that a failure in an early block silently skipped everything after it.
set -e

# Each block says what it is doing and when it started.
#
# This is not decoration. apt is quietened below, and its output used to be the only sign that
# this script - the longest stretch of the whole setup - was still alive. One line per block
# replaces several hundred, and the timestamps are what make a run's timing readable afterwards.
# Local time, like 01_setup.ps1 and unlike the container logs, which are UTC.
step() {
    echo ""
    echo "--> [$(date +%H:%M:%S)] $*"
}

# Quieten apt, which is by far the noisiest thing in this script. Package lists and unpacking
# progress are not read unless something fails, so stdout goes to /dev/null - and stderr does
# not, so a failure still says why and "set -e" still stops the script.
#
# "apt-get" rather than "apt" everywhere, because "apt" writes a warning about its unstable CLI
# to stderr, which is exactly the stream being kept.
export DEBIAN_FRONTEND=noninteractive

apt_get() {
    apt-get -qq -y "$@" >/dev/null
}

# setup DNS
# DNS inside of WSL2 is sometimes a problem
# In the beginning, /etc/resolv.conf is a symlink to /mnt/wsl/resolv.conf and name resolution works
# Problem: Sometimes, etc/resolv.conf is a symlink to ../run/systemd/resolve/stub-resolv.conf and it does not work
# Workaround 1: Configure a static /etc/resolv.conf with the DNS server of your choice
# Problem: Sometimes, etc/resolv.conf is removed again and recreated as a symlink to ../run/systemd/resolve/stub-resolv.conf
#echo "[network]" >> /etc/wsl.conf && \
#echo "generateResolvConf = false" >> /etc/wsl.conf && \
#rm /etc/resolv.conf && \
#echo "nameserver 1.1.1.1" > /etc/resolv.conf && \
# Workaround 2: Configure systemd-resolved with the DNS server of your choice
# Problem: Not tested yet
#echo "DNS=1.1.1.1" >> /etc/systemd/resolved.conf && \

# update packages
step "Updating the package lists"
apt_get update
apt_get upgrade

# install pwsh
# https://docs.microsoft.com/de-de/powershell/scripting/install/install-ubuntu
step "Installing PowerShell"
apt_get install wget apt-transport-https software-properties-common
wget -q -O /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null
apt_get update
apt_get install powershell

# install docker
# https://docs.docker.com/engine/install/ubuntu/
step "Installing docker"
apt_get install ca-certificates curl gnupg2 lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt_get update
apt_get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
update-alternatives --set iptables /usr/sbin/iptables-legacy
service docker start
# As of April 2025, we need a restart so that docker can setup the network for the containers.
# But as we need a restart of the WSL2, we currently don't need this.
# service docker restart

# install 7zip
step "Installing 7-Zip"
apt_get install p7zip-full

# To pull and save the docker images:
# docker pull mcr.microsoft.com/mssql/server:2025-CU5-ubuntu-24.04
# docker save -o /mnt/c/tmp/DockerImages/SQLServer.tar mcr.microsoft.com/mssql/server:2025-CU5-ubuntu-24.04
# docker pull container-registry.oracle.com/database/express:21.3.0-xe
# docker save -o /mnt/c/tmp/DockerImages/Oracle.tar container-registry.oracle.com/database/express:21.3.0-xe

# Load docker images from files to save time and download data volume
#
# Its own step line, because this is where the minutes go on a machine that has the tars - two
# large images read off disk. Without it that time is billed to the 7-Zip step above, which
# measured at nearly four minutes on the first run that had these banners.
if [ -f "/mnt/c/tmp/DockerImages/SQLServer.tar" ] || [ -f "/mnt/c/tmp/DockerImages/Oracle.tar" ]; then
    step "Loading the saved docker images"
fi

if [ -f "/mnt/c/tmp/DockerImages/SQLServer.tar" ]; then
    if ! docker image inspect mcr.microsoft.com/mssql/server:2025-CU5-ubuntu-24.04 >/dev/null 2>&1; then
        echo "Loading docker image 2025-CU5-ubuntu-24.04 for SQL Server from file..."
        docker load -i /mnt/c/tmp/DockerImages/SQLServer.tar
        if ! docker image inspect mcr.microsoft.com/mssql/server:2025-CU5-ubuntu-24.04 >/dev/null 2>&1; then
            echo "Failed to load SQL Server image, exiting with error."
            exit 1
        fi
    else
        echo "SQL Server image already present, skipping load."
    fi
fi

if [ -f "/mnt/c/tmp/DockerImages/Oracle.tar" ]; then
    if ! docker image inspect container-registry.oracle.com/database/express:21.3.0-xe >/dev/null 2>&1; then
        echo "Loading docker image 21.3.0-xe for Oracle from file..."
        docker load -i /mnt/c/tmp/DockerImages/Oracle.tar
        if ! docker image inspect container-registry.oracle.com/database/express:21.3.0-xe >/dev/null 2>&1; then
            echo "Failed to load Oracle image, exiting with error."
            exit 1
        fi
    else
        echo "Oracle image already present, skipping load."
    fi
fi
