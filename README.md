![logo](logo.jpg)
# PowerShell moves Data around

This repository provides infrastructure as code, sample data and demo code to show how PowerShell can move data around.
It is intended to show the strengths and possibilities of PowerShell as an ETL tool.

The code is based on some of my customer projects, but has been greatly simplified and standardized in some places.
This repository is intended to help you set up an initial proof of concept. However, the code is not suitable for direct productive use.
If you would like assistance with productive use, please contact me.

There is a sibling project that does the same things in Python:
[Python moves Data around](https://github.com/andreasjordan/Python-moves-Data-around). The two are
meant to be shown next to each other, and they are meant to live in the same WSL2 installation - see
[Sharing one WSL2 installation with the sibling repository](#sharing-one-wsl2-installation-with-the-sibling-repository).



## Supported data sources and targets

- Microsoft SQL Server
- Oracle database
- PostgreSQL
- MongoDB
- Apache Kafka (Redpanda)
- Microsoft Excel
- JSON files
- XML files
- GPX files
- JPEG files



## Supported PowerShell versions and operating systems

Some functionality can be used (and some can be changed to work) with Windows PowerShell 5.1, but most of the code is targeted at PowerShell 7, and is developed and run against the current 7.x release.

`01_setup.ps1` itself needs PowerShell 7, because it downloads and loads the database drivers to check that they work on this side.

The code is both tested on Windows 11 and an Ubuntu WSL2.

## What you install, and what the setup installs

**The setup installs into WSL2 and into this repository. It installs nothing on your machine and
changes nothing about how your machine is configured** - in particular it does not make the PSGallery
a trusted repository for you, which is not this repository's decision to make.

Your machine needs three things, and that is the whole list:

1. **PowerShell 7.5 or later**, which is what the demos ask for.
2. **The modules in `modules.txt`**, installed for your user:
   ```powershell
   Install-Module -Name (Get-Content ./modules.txt) -Scope CurrentUser
   ```
   The PSGallery may ask you to confirm that you trust it. That prompt is the point.
3. **WSL2**, with a default distribution - see [Install WSL2](#install-wsl2) below. Everything else the
   setup needs goes inside it, and you can throw it away and start again at any time.

`00_check_host.ps1` checks all three, names every one that is missing together with the command that
installs it, and changes nothing. `01_setup.ps1` runs it first, and you can run it on its own whenever
you like:

```powershell
.\00_check_host.ps1
```



## Repository layout

| Path | Content |
| --- | --- |
| `00_check_host.ps1` | Checks that this machine has what the setup will not install, and names anything missing. Changes nothing, so it is safe to run at any time. |
| `01_setup.ps1` … `06_test_connections.ps1` | The setup steps. `01_setup.ps1` runs all of them. It builds the environment; it does not start a demo. |
| `07_check_ports.ps1` | Not a setup step. Checks whether Windows can reach the container ports, for when something cannot connect. |
| `modules.txt` | The list of PowerShell modules the demos need. Both installs read it. |
| `start_demo.ps1` | Starts the containers and keeps them running. This is what you run before a demo. |
| `data/` | One directory per scenario for the sample data. The generated and downloaded files are not part of the repository. |
| `demo/` | The demo scripts, plus an `init_<scenario>.ps1` per scenario that opens the needed connections. |
| `docker/` | The compose file, the database init scripts and the PhotoService application. |
| `lib/` | The functions that do the actual work. See [lib/README.md](lib/README.md) for an overview. |
| `verify/` | Scripts that check the demos still do what they claim, against the running containers. Not a test suite and not part of the setup — see [verify/README.md](verify/README.md). Run `.\verify\Invoke-Verify.ps1` when you want to know that everything still works. |



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

- Setup: XML files will be downloaded from archive.org/download/stackexchange
- Data from XML files will be imported into SQL Server database
- Data will be streamed between databases and database systems
- Data from XML files will be imported into MongoDB database

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
- Change Data Capture is used to find what changed

This scenario needs PowerShell 7.

The application container is the source of every customer and order the second half of this demo
transfers, and it staggers its work over the first two minutes after it starts: the first order at
60 seconds, the first payment at 90, the first shipment at 120. Give it that couple of minutes before
expecting anything to be there - inside that window the demo looks broken and is not.


### Event streaming

- Setup: The PhotoService application is running inside of a container and produces an event to a Kafka topic whenever something happens
- The `order_event` outbox table shows the pattern you may already have, and where its limits are
- The same events are read from the topic with a consumer group
- The events are replayed into SQL Server, incrementally, using the group's committed offsets
- A second consumer group with no history rebuilds the target from the whole topic
- The high watermark is what makes "read everything" terminate on a topic that is still being written to

This scenario needs PowerShell 7.

Kafka is served by [Redpanda](https://www.redpanda.com/), which speaks the Kafka protocol, so every
client and every word in the demo is Kafka. The same two-minute wait as PhotoService applies, and
more strictly: this demo reads the events rather than the tables, so before the first order there is
nothing on the topic but `Added customer`.


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

These containers are used: SQL Server 2025, Oracle Database Express Edition 21c, PostgreSQL with PostGIS, pgAdmin, MongoDB, Redpanda with its console, and one running the PhotoService application. The exact image versions are pinned in `docker/docker-compose.yaml`.

Two of the containers have a web interface:

- Redpanda Console: http://127.0.0.1:8080
- pgAdmin: http://127.0.0.1:5050/browser/

All accounts use the same password. As this is a demo environment that only runs locally, the password
is part of the repository. `docker/.env` is where it is configured for the containers themselves, and
`04_docker_compose.sh` reads it from there - but the `CREATE USER` statements in the init SQL still have
it as a literal, so changing `docker/.env` alone is not enough to change it everywhere.

The initial PowerShell code must be run inside WSL2 to set up the sample data.

The demo PowerShell code can be executed either inside WSL2 or on the Windows 11 system. However, to run all demos, PowerShell 7.5 or later is required.

A video of the installation is available here: https://youtu.be/0NNNqPau4Go — it shows
`start_containers.ps1`, which is now `start_demo.ps1`.


### Sharing one WSL2 installation with the sibling repository

Both repositories are meant to live in the same WSL2 installation. Neither one names a distribution, so
both use the default - install Ubuntu once, then run `01_setup.ps1` in each repository. The second run
finds docker and 7-Zip already there and only does its own half. The volumes belong to the stack rather
than to the machine, so each repository builds its own.

`01_setup.ps1` **sets the machine up, it does not start a demo.** It stops the containers again at the
end, which is what makes running it in both repositories possible: the other setup would otherwise find
these containers holding every port it wants.

To demo, run `start_demo.ps1`. Both repositories publish the same ports, so only one stack can run at a
time, and `start_demo.ps1` stops the other one for you before starting its own. That is a stop and not
a `down`, so the volumes on both sides survive - switching back and forth costs a minute.

Why it stops the other stack rather than letting the ports collide: both repositories use the same
ports, the same password *and* the same database names. A port conflict would at least be loud. Instead
the other stack answers every connection, so a demo started while the sibling is up does not fail - it
succeeds against the wrong volumes.

To see which stack is currently running:

```
wsl --user root docker compose ls
```

**One small thing about switching.** It restarts the PhotoService container, which truncates its tables
and restarts its schedule - so demos 04 and 06 are empty for the first two minutes after every
switch, on whichever side you switch to.


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

To run all setup steps, simply execute `01_setup.ps1` in a non-elevated PowerShell 7. It shells into
WSL2 for most of them, and finishes on the Windows side:

| Step | Runs as | What it does |
| --- | --- | --- |
| `00_check_host.ps1` | you, on Windows | Checks that this machine has PowerShell 7.5, the modules in `modules.txt` and a WSL2 distribution, and stops with a list if it has not. Installs nothing. First, because it is the only step that costs nothing when it fails |
| `02_wsl2_setup.sh` | root, in WSL2 | PowerShell, Docker and 7-Zip |
| `03_pwsh_setup.ps1` | root, in WSL2 | The modules in `modules.txt`, machine-wide so that the PhotoService container can mount them - and the database drivers into `lib/`, including the Linux build of librdkafka that the container needs |
| `03_pwsh_setup.ps1` again | you, on Windows | The same script, which on Windows only downloads the drivers into `lib/` - Oracle, Npgsql and Confluent.Kafka with the *Windows* build of its native librdkafka - and loads them, which is the check that this side can. It installs nothing on your machine. Both driver steps run before the containers start, because `lib/` is mounted read only into the PhotoService container and it can load a driver but never download one |
| `04_docker_compose.sh` | root, in WSL2 | Waits for the docker daemon, starts the containers, and waits until SQL Server, PostgreSQL, MongoDB and Oracle have created the demo databases |
| `05_sample_data_setup.ps1` | you, in WSL2 | Creates the Excel files from `sample.json` and downloads the StackExchange and Geodata samples. A download is skipped when its files are already there; `-Force` fetches them again |
| `06_test_connections.ps1` | you, in WSL2 | Opens a connection to every database a demo uses |
| `06_test_connections.ps1` again | you, on Windows | Waits until Windows can reach the container ports, then runs the same check from the side that runs the demos |
| `docker compose stop` | root, in WSL2 | Stops the containers again. The setup is finished; `start_demo.ps1` is what starts a demo |

Every step announces itself before it runs, and the slow ones say roughly how long they take -
`04_docker_compose.sh` is quiet for about two minutes while it waits for Oracle, and a quiet stretch
with no output is hard to tell from a script that has hung.

The first and last rows are not an afterthought. The demos are usually run from Windows, so without them
the setup can finish green while a module or a driver is missing on that side. And the two runs of `06`
do not prove the same thing: the one in WSL2 reaches the containers over the WSL2 loopback, while the
one on Windows goes through the port forwarding that Windows sets up. Those forwards do not all appear
at the same moment, which is why the last step waits for them first - a connection refused from Windows
usually means the forward is not there yet, not that the database is down.

The last three rows all run on the Windows side, so the script holds WSL2 open with a background `wsl`
process while they do. Without it WSL2 shuts the distribution down a few seconds after its last command
finishes and takes every container with it, and the connection test then fails against databases that
are no longer running.

A failure in the connection test from Windows does not stop the script before the stop below - the
script reports the failure once the containers are down, and `start_demo.ps1` brings them back in a
minute if you want to look into it.

The whole run takes about half an hour. If you are installing both repositories, see
[Sharing one WSL2 installation with the sibling repository](#sharing-one-wsl2-installation-with-the-sibling-repository).


### Start the demo

Execute `start_demo.ps1` in a non-elevated PowerShell. It starts the containers, waits until the
databases answer, and then sits in a WSL2 shell. **If you exit that shell, WSL2 shuts down and takes
the containers with it**, so leave the window open for as long as you are demoing.

This keeps all data. It is a start, not a reset - the volumes survive, so every table a demo wrote last
time is still there. One thing to expect in `docker compose logs sqlserver` afterwards: its init script
runs on every start and its `CREATE LOGIN` / `CREATE DATABASE` statements are unconditional, so the log
fills with "already exists" errors. They are harmless and the databases are fine.

Run this after a reboot too, and whenever you are switching back from the sibling repository - it stops
that repository's containers first, because both publish the same ports.


### Reset the containers

A demo leaves data behind, and the next run of the same demo may not like it. There are two levels of
reset, and the cheap one is usually the one you want.

Both commands below are run from the repository directory, and both need the containers to be up -
they talk to the docker daemon inside WSL2. If WSL2 has been shut down, run `start_demo.ps1` first,
because that is what starts the daemon.

**Just the PhotoService application.** This is what demos 04 and 06 need, and it costs seconds:

```
wsl --cd "$PWD\docker" --user root docker compose restart photoservice
```

The application clears its own PostgreSQL tables and its MongoDB collection when it starts, and empties
the Kafka topic, so this puts it back to nothing. It also restarts the clock: the first order is
scheduled 60 seconds later, the first payment at 90, the first shipment at 120.

**Everything, back to how the setup left it:**

```
wsl --cd "$PWD\docker" --user root docker compose down -v
.\start_demo.ps1
```

`-v` is the whole point - it removes the named volumes, and that is what actually deletes the data.
Without it you get the restart described above. With it, every container starts empty and re-runs its
init scripts, so all five scenario databases are created again exactly as the setup made them.

**It costs about two minutes**, because the Oracle image ships a prebuilt database rather than creating
one on first start. It does not re-download the images. Use it whenever you want a genuinely clean lab -
the only thing it costs you is whatever you had not saved.

It is also the only way to pick up a change to the init SQL under `docker/`, because those scripts run
only when a volume is created.


### When something cannot connect

Execute `07_check_ports.ps1` in a second PowerShell window, while the other one sits in its WSL2
shell. For every published port it says whether Windows has a listener for it and whether a connection
gets through:

```
1433   SQL Server         CONNECT   listener on ::1 (wslrelay)
1521   Oracle             CONNECT   listener on ::1 (wslrelay)
...
```

`NO LISTENER` means Windows has not published that container port yet. The database is very probably
running and answering fine inside WSL2 - the forward is what is missing, and the usual answer is to
wait a little. This is worth knowing because a driver reports it as an error about the *database*, when
in fact nothing was listening on this side to refuse the connection.

If every port connects and a demo still cannot reach a database, the network is not the problem - run
`06_test_connections.ps1`, which asks the drivers rather than the sockets.
