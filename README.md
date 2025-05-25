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
- Micosoft Excel
- JSON files
- XML files
- GPX files



## Supported PowerShell versions and operating systems

Some functionality can be used (and some can be changed to work) with Windows PowerShell 5.1, but most of the code is targeted at PowerShell 7 and tested with the current version PowerShell 7.5.1.

The code is both tested on Windows 11 and an Ubuntu WSL2.



## Demo scenarios

### Timesheets

- Setup: Excel files will be created from sample data
- Excel files will be imported into SQL Server database
- Excel file will be created with data from SQL Server database

This scenario can be run with both PowerShell 5.1 and PowerShell 7.


### StackExchange

- Setup: XML files will be downloaded from archive.org/download/stackexchange and uploaded to MinIO
- Data from XML files will be imported into SQL Server database
- Data will be streamed between databases and database systems
- Data from XML files will be imported into MongoDB database
- XML files will be downloaded from MinIO

This scenario needs PowerShell 7.


### Geodata

- Setup: GPX files will be downloaded from berlin.de/sen/uvk/mobilitaet-und-verkehr/verkehrsplanung/radverkehr/radverkehrsnetz/radrouten/gpx/
- Setup: GPX files will be downloaded from michael-mueller-verlag.de/de/reisefuehrer/deutschland/berlin-city/gps-daten/
- Setup: JSON file will be downloaded from datahub.io/core/geo-countries
- Data from GPX files will be imported into SQL Server database
MORE DEMO CODE WILL BE PUBLISHED LATER...

This scenario need PowerShell 7.


### PhotoService

- Setup: The PhotoService application is running inside of a container and is constantly creating data
- Binary data with jpeg images is imported to PostgreSQL
MORE DEMO CODE WILL BE PUBLISHED LATER...

This scenario need PowerShell 7.



## Infrastructure

The repository is designed for and tested on a Windows 11 system with 32 GB of RAM. The WSL2 is configured with docker to run the databases inside of containers.

The initial PowerShell code needs to be run inside the WSL2 to setup the sample data.

The demo PowerShell code can run both inside the WSL2 or on the Windows 11 system. But for all demos to work, you need at least PowerShell 7.5.


### Step by step setup

Download and extract or clone this repository to a location of your choice.

Setup WSL2. I use the default image Ubuntu by just executing `wsl --install` in an elevated cmd or powershell on a current Windows 11 systems. To start from scratch you can remove the Ubuntu by running `wsl --unregister Ubuntu`. Start Ubuntu via start menu and follow the instructions to create the unix account. The name of the accout and the password don't matter - use a short password as you need it from time to time for sudo.

Use the windows explorer to navigate to the base folder, right click on "01_wsl2_get_symlink_part1.ps1" and use "execute with powershell" to execute this small one liner. It builds the unix commandline to add a symbolic link from /mnt/powershell-moves-data-around to the base folder inside of the wsl and then executes all the following scripts. This commandline is copied to the clipboard so that you can just past it inside on the WSL2 for an easy start.

If you don't like that solution, just navigate to the base folder inside of the WSL2 and then execute all the scripts in the base folder. Start with the shell script "02_wsl2_setup.sh" with `sudo ./02_wsl2_setup.sh`.

If you already have an environment that you want to use, please have a look at the contents of "02_wsl2_setup.sh" to setup the needed components.

To be able to connect to the database systems, some PowerShell modules and .NET libraries are needed. To download them, execute "03_pwsh_setup.ps1" with `sudo pwsh ./03_pwsh_setup.ps1`. As we also need the PowerShell modules inside of a container, it it important to run the command with sudo to install them in the "all users" scope to "/usr/local/share/powershell/Modules". This script can also be used to setup powershell on the Windows system. Make sure to execute it with PowerShell 7, PowerShell 5.1 is not supported.

At this point, the command line from "01_wsl2_get_symlink_part1.ps1" uses "wsl.exe --shutdown" to shutdown the WSL2. I still don't know exactly why, but if we start docker compose before rebooting the WSL2, the containers are reachable from the host, but can not connect to each other or the internet.

After we have started the WSL2 again, right click on "01_wsl2_get_symlink_part2.ps1" and use "execute with powershell" to execute this small one liner for the second part of the setup. This will change the directory to the base folder and then starts the rest of the scripts.

Now we can start the docker containers with "sudo docker compose up -d" inside of the directory "docker" or by executing the script "04_docker_compose.sh" with `sudo ./04_docker_compose.sh`. This might take a long time as big images like oracle are pulled from the internet.

Only a small part of the sample data is included in this repository, most of data needs to be downloaded from the internet and processed. This is done by the PowerShell script "05_sample_data_setup.ps1" which can be executed with `pwsh ./05_sample_data_setup.ps1`.

To test the connections to the databases inside of the docker containers, the script "06_test_connections.ps1" is executed as the last part of the setup with `pwsh ./06_test_connections.ps1`.
