#!/bin/bash

# setup DNS
echo "[network]" >> /etc/wsl.conf && \
echo "generateResolvConf = false" >> /etc/wsl.conf && \
rm /etc/resolv.conf && \
echo "nameserver 1.1.1.1" > /etc/resolv.conf && \

# update packages
apt update && \
apt -y upgrade && \

# install pwsh
# https://docs.microsoft.com/de-de/powershell/scripting/install/install-ubuntu
apt-get install -y wget apt-transport-https software-properties-common && \
wget -q -O /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" && \
dpkg -i /tmp/packages-microsoft-prod.deb && \
apt-get update && \
apt-get install -y powershell && \

# install docker
# https://docs.docker.com/engine/install/ubuntu/
apt-get install -y ca-certificates curl gnupg2 lsb-release && \
mkdir -p /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
apt update && \
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
update-alternatives --set iptables /usr/sbin/iptables-legacy && \
service docker start && \
# As of April 2025, we need a restart so that docker can setup the network for the containers.
# But as we need a restart of the WSL2, we currently don't need this.
# service docker restart && \

# install 7zip
apt-get install -y p7zip-full && \

# Load docker images from files to save time and download data volume
if [ -f "/mnt/c/tmp/DockerImages/SQLServer.tar.gz" ]; then
    echo "Loading docker image for SQL Server from file..."
    docker load -i /mnt/c/tmp/DockerImages/SQLServer.tar.gz
fi
if [ -f "/mnt/c/tmp/DockerImages/Oracle.tar.gz" ]; then
    echo "Loading docker image for Oracle from file..."
    docker load -i /mnt/c/tmp/DockerImages/Oracle.tar.gz
fi
