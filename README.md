![logo](logo.jpg)
# PowerShell moves Data around

This repository provides infrastructure as code, sample data and demo code to show how PowerShell can move data around.
It is intended to show the strengths and possibilities of PowerShell as an ETL tool.

The code is based on some of my customer projects, but has been greatly simplified and standardized in some places.
This repository is intended to help you set up an initial proof of concept. However, the code is not suitable for direct productive use.
If you would like assistance with productive use, please contact me.



## Supported data sources and targets

- Microsoft SQL Server
- Oracle database
- PostgreSQL
- MongoDB
- MinIO
- Microsoft Excel
- JSON files
- XML files
- GPX files
- JPEG files



## Supported PowerShell versions and operating systems

Some functionality can be used (and some can be changed to work) with Windows PowerShell 5.1, but most of the code is targeted at PowerShell 7 and tested with the current version PowerShell 7.5.1.

The code is both tested on Windows 11 and an Ubuntu WSL2.



## Demo scenarios

### Timesheets

- Setup: Excel files will be created from sample data
- Excel files will be imported into SQL Server database
- Excel file will be created with data from SQL Server database

This scenario can be run with both PowerShell 5.1 and PowerShell 7.

I have recorded a [Video](https://youtu.be/UnTFhbC3JVE) of the demo.


### StackExchange

- Setup: XML files will be downloaded from archive.org/download/stackexchange and uploaded to MinIO
- Data from XML files will be imported into SQL Server database
- Data will be streamed between databases and database systems
- Data from XML files will be imported into MongoDB database
- XML files will be downloaded from MinIO

This scenario needs PowerShell 7.

I have recorded a [Video](https://youtu.be/EK1a7WthRqA) of the demo.


### Geodata

- Setup: GPX files will be downloaded from berlin.de/sen/uvk/mobilitaet-und-verkehr/verkehrsplanung/radverkehr/radverkehrsnetz/radrouten/gpx/
- Setup: GPX files will be downloaded from michael-mueller-verlag.de/de/reisefuehrer/deutschland/berlin-city/gps-daten/
- Setup: JSON file will be downloaded from datahub.io/core/geo-countries
- Data from GPX files will be imported into SQL Server database
- Geodata will be transfered from SQL Server to PostgreSQL and Oracle
- Data from JSON file will be imported into Oracle and PostgreSQL database
- Data from the german "Mauttabelle" will be imported into Oracle and PostgreSQL database

This scenario needs PowerShell 7.


### PhotoService

- Setup: The PhotoService application is running inside of a container and is constantly creating data
- Binary data with jpeg images is imported to PostgreSQL
- Binary data with jpeg images is transfered from PostgreSQL to SQL Server
- Application data is transfered from PostgreSQL to SQL Server
- Only new data is transfered
- Updated data is transfered
- Transactions are used to ensure data integrity
- Event data is used to update tables in SQL Server

This scenario needs PowerShell 7.



## Infrastructure

The repository is designed for and tested on a Windows 11 system with 32 GB of RAM. The WSL2 is configured with docker to run the databases inside of containers.

The initial PowerShell code needs to be run inside the WSL2 to setup the sample data.

The demo PowerShell code can run both inside the WSL2 or on the Windows 11 system. But for all demos to work, you need at least PowerShell 7.5.

A video of the installation is available here: https://youtu.be/0NNNqPau4Go


### Install WSL2

I use the default image Ubuntu by just executing `wsl --install` in an elevated cmd or powershell on a current Windows 11 systems. To start from scratch you can remove the Ubuntu by running `wsl --unregister Ubuntu`. Start Ubuntu with `wsl` and follow the instructions to create the unix account. The name of the accout and the password don't matter.


### Clone or download the repository

Open a non-elevated powershell.exe and go to a folder of your choice, I will use "C:\tmp" in this guide:

```
if (-not (Test-Path -Path C:\tmp)) {
    $null = New-Item -Path C:\tmp -ItemType Directory
}
Set-Location -Path C:\tmp
```

If you have git installed, you can just clone the repository:

```
git clone https://github.com/andreasjordan/PowerShell-moves-Data-around.git
```

Or you can download and extract the repository:

```
[Net.WebClient]::new().DownloadFile('https://github.com/andreasjordan/PowerShell-moves-Data-around/archive/refs/heads/main.zip', "$PWD\PowerShell-moves-Data-around.zip")
Expand-Archive -Path $PWD\PowerShell-moves-Data-around.zip -DestinationPath $PWD
Rename-Item -Path $PWD\PowerShell-moves-Data-around-main -NewName PowerShell-moves-Data-around
Remove-Item -Path $PWD\PowerShell-moves-Data-around.zip
Get-ChildItem -Path $PWD\PowerShell-moves-Data-around -Filter *.ps1 -Recurse | Unblock-File
```


### Start the installation

To run all the setup steps just execute "01_setup.ps1" in a non-elevated powershell.exe:

```
.\PowerShell-moves-Data-around\01_setup.ps1
```

At the end, the script enters the WSL2 to keep all docker containers running. If you exit, it will shutdown WSL2 with all containers.


### Restart the docker containers

To restart the containers use "99_start.ps1":

```
.\PowerShell-moves-Data-around\99_start.ps1
```
