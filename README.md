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



## Repository layout

| Path | Content |
| --- | --- |
| `01_setup.ps1` … `06_test_connections.ps1` | The setup steps. `01_setup.ps1` runs all of them. |
| `start_containers.ps1` | Restarts the containers after a reboot. |
| `data/` | One directory per scenario for the sample data. The generated and downloaded files are not part of the repository. |
| `demo/` | The demo scripts, plus an `init_<scenario>.ps1` per scenario that opens the needed connections. |
| `docker/` | The compose file, the database init scripts and the PhotoService application. |
| `lib/` | The functions that do the actual work. See [lib/README.md](lib/README.md) for an overview. |



## Running the demos

The demo scripts are **not meant to be executed as a whole**. Each one starts with a `break` statement
to prevent that. They are meant to be opened in an editor like Visual Studio Code and then executed
section by section, so that you can look at the data and the results at every step.

The `demo/init_<scenario>.ps1` scripts are different: they only set up the connections for a scenario
and can be run as they are.



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


### ProjectStatus

- Setup: An Excel file will be created from sample data
- Data from the Excel file will be imported into SQL Server database
- A bulk import fails on the first invalid row and imports nothing at all
- Data will be imported row by row with a parameterized INSERT statement
- Exceptions are used to identify the rows that could not be imported
- The failed rows will be exported to a new Excel file together with the error message
- Some of the failures will be corrected automatically and imported on a second try

This scenario can be run with both PowerShell 5.1 and PowerShell 7.



## Infrastructure

The repository is designed for and tested on a Windows 11 system with 32 GB of RAM. WSL2 is configured with Docker to run the databases inside containers.

These containers are used: SQL Server 2025, Oracle Database Express Edition 21c, PostgreSQL with PostGIS, pgAdmin, MongoDB, MinIO, and one running the PhotoService application. The exact image versions are pinned in `docker/docker-compose.yaml`.

Two of the containers have a web interface:

- MinIO: http://127.0.0.1:9001/login
- pgAdmin: http://127.0.0.1:5050/browser/

All accounts use the same password, which is configured in `docker/.env`. As this is a demo environment that only runs locally, the password is part of the repository.

The initial PowerShell code must be run inside WSL2 to set up the sample data.

The demo PowerShell code can be executed either inside WSL2 or on the Windows 11 system. However, to run all demos, PowerShell 7.5 or later is required.

A video of the installation is available here: https://youtu.be/0NNNqPau4Go


### Install WSL2

I use the Ubuntu 24.04 image by running `wsl --install -d Ubuntu-24.04` in an elevated Command Prompt or PowerShell on a current Windows 11 system. To start from scratch, you can remove Ubuntu by running `wsl --unregister Ubuntu-24.04`. At the end of the installation, Ubuntu starts automatically, and you are prompted to create a Unix user account. The username and password do not matter.


### Clone or download the repository

Open a non-elevated PowerShell and navigate to a folder of your choice. In this guide, I will use `C:\tmp`.

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

To run all setup steps, simply execute `01_setup.ps1` in a non-elevated PowerShell.

At the end, the script enters WSL2 to keep all Docker containers running. If you exit, WSL2 will shut down along with all containers.


### Restart the docker containers

To restart the containers, simply execute `start_containers.ps1` in a non-elevated PowerShell.
