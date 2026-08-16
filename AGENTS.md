# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this repository is

A teaching and demo repository that accompanies talks and videos: infrastructure as code, sample data
and demo code showing how PowerShell can move data around. It is deliberately **not production code**
(see `README.md`).

It has a sibling: [Python moves Data around](https://github.com/andreasjordan/Python-moves-Data-around),
a port of this repository scenario by scenario. The two are presented **side by side in one session**,
so a change here is also a change to one half of a comparison:

- **When something is wrong in the sibling and you cannot reach it, append an entry to
  `SIBLING-FINDINGS.md`** rather than fixing it there. **If both repositories are open** — a VS Code
  workspace holding the two of them — fix it in place instead, and commit per repository. Say which of
  the two situations you are in before the first change on the other side.
- The sibling keeps the reasoning behind every place the two differ in its `DIFFERENCES.md`. When a
  change here would make a documented difference wrong, say so.

**Prime directive:** optimize every change for *readability while being shown on a projector*, not for
robustness, genericity or production hardening. If a change makes the code shorter and clearer, it is
probably right. If it adds abstraction, indirection or defensive layers, it is probably wrong.

## Current state — read this before assuming anything works

| Area | State |
| --- | --- |
| `demo/01_timesheets.ps1` … `06_eventstreaming.ps1` | Complete, and stepped through section by section. Demo 6 has not been presented to an audience yet. |
| `lib/` | 41 functions. The grid in `lib/README.md` says which cells are deliberately empty. |
| The setup chain | `01_setup.ps1` **builds only** — it stops the containers at the end, so it can be run in this repository and then in the sibling, in either order. `start_demo.ps1` is what starts a demo. |
| `06_test_connections.ps1` | Run **twice** by `01_setup.ps1`: once inside WSL2 and once on Windows, because the demos run from Windows and nothing else checks that side. One block per scenario and per provider. |
| MinIO | Gone from the lab: the container, its init script, the two policies and the `.env` block are deleted, and no demo or setup script mentions it. **The five `lib/*-Mio*.ps1` files are deliberately kept** — `lib/README.md` has a *"MinIO is out of the lab, and the code is kept anyway"* section with a worked example of all five, which is the archive. The hand-rolled signing there is **AWS Signature Version 2**, not SigV4. Do not build anything new on it, and do not delete it either. |
| `docker/photoservice-app.ps1` | The shop that keeps inventing customers and orders. **It is the source of everything the second half of demo 04 transfers and of every event demo 06 reads**, so those cells have nothing to find unless this container is running — and it staggers its work over the first two minutes after it starts: the first order at 60 s, the first payment at 90 s, the first shipment at 120 s. `docker compose restart photoservice` is the cheap reset: it truncates its PostgreSQL tables, drops its MongoDB collection, empties the Kafka topic and restarts that clock. Keep the schedule in step with the sibling's `photoservice-app.py`. |
| The outbox is a real transaction | `photoservice-app.ps1` wraps the `UPDATE order_header` and the `INSERT INTO order_event` in one `BeginTransaction`, for payments and for shipments. **Do not split them again** — the invariant is checked by `verify/06_eventstreaming.ps1`, in both directions and with a precondition that there were rows to compare. The order header and its details are one transaction too; what is deliberate there is that the Kafka events are produced *after* the commit, never inside it. |
| The topic is emptied at startup | `Remove-KfkTopic` is called next to `Remove-MdbCollection`, so the reset is complete. The application restarts its ids at 1, so a topic that outlives the tables holds one `Added customer` with `id = 1` per start, and demo 06's replay dies on `Violation of PRIMARY KEY constraint 'customer_pk'`. **The history demo 06 teaches is across readers, not across application starts** — a new group id still replays the whole topic. |
| Stored timestamps are truncated to milliseconds | `Get-LocalTimestamp` hands over whole milliseconds because every column that receives one is `TIMESTAMP(3)`. Otherwise the topic carries `09:46:49.0523691` while PostgreSQL holds `09:46:49.052`, and a replay through demo 06 lands a different value in SQL Server than demo 04's direct transfer. |
| `lib/Write-PgTable.ps1` | Loads through `COPY`, using Npgsql's `BeginTextImport` — the counterpart of the `SqlBulkCopy` and `OracleBulkCopy` its two siblings use. The copy format is text, so `DateTime` and `byte[]` are formatted by hand and `-BatchSize` only paces the progress bar; read the notes in `lib/README.md` before touching any of that. |
| The Azure SQL bonus sections | At the end of `demo/02_stackexchange.ps1` and `demo/04_photoservice.ps1`. They need Azure resources, the `Az` module, a firewall rule and two environment variables, so they are not local and are not part of a normal run. |
| Oracle's first start | **About two minutes, not fifteen.** The image ships a prebuilt XE and starts it; there is no database-creation phase. The 15 minutes in `wait_for` is a timeout margin, not a measurement. Do not repeat a duration you have not measured. |

## Demo scripts are stepped through, never run

`demo/01_timesheets.ps1`, `02_stackexchange.ps1`, `03_geodata.ps1`, `04_photoservice.ps1`,
`05_projectstatus.ps1` and `06_eventstreaming.ps1` all begin with a bare `break` on line 1. That is
deliberate: the file is opened in VS Code and executed section by section (F8 on a selection),
telling a story as it goes.

- Never remove the `break`.
- Never restructure a demo so it can run end to end.
- Never execute a demo script.

Variables assigned but never used again, the same Excel file imported several times, and
`Format-Table` / `Out-GridView` / `Out-ConsoleGridView` calls are **pedagogical, not dead code**. Do not
flag or remove them.

Scripts that *are* meant to run: the numbered scripts in the repository root, `start_demo.ps1`,
`demo/init_*.ps1`, and `demo/04_photoservice_transfer_01.ps1`. `demo/Import-GpxFile.ps1` and
`demo/Import-XlsTimesheet.ps1` only define a function and are dot-sourced.

`07_check_ports.ps1` is **not** part of the setup sequence and `01_setup.ps1` does not run it. It is a
read-only diagnostic and it is safe for an agent to run: it opens and closes TCP connections from
Windows and starts nothing.

`00_check_host.ps1` **is** the first step of the setup sequence, and it is also safe to run on its own:
it reads a version, a module list and the registry, and it installs and changes nothing. It does start
the default WSL2 distribution, which costs a few seconds.

## The setup chain, and what is load-bearing in it

Four things in `04_docker_compose.sh` exist because the failure each one prevents is silent or
misleading. Do not simplify them away.

**It waits for the demo databases, not for the server.** The databases are created after the server
starts accepting connections, so a check that only asks "does it answer" returns too early.

**Do not wait by grepping the container log** for the init script's `SQL Server configuration complete.`
message. `docker logs` keeps the output of earlier runs, so on a restarted container it matches
immediately, while the server is still starting. It looks like a fix and silently keeps the race. Query
`sys.databases` instead.

**It waits for the docker daemon first.** `02_wsl2_setup.sh` starts docker, but `01_setup.ps1` then runs
`wsl --shutdown`, and `start_demo.ps1` runs after a reboot — so in both cases the daemon has to come up
again, and it only does because systemd starts it. That is a race right after WSL2 boots.

**`wait_for` gives up when the container has stopped**, instead of sitting out the full 5 or 15 minutes,
and the failure path prints `docker compose logs --tail 50`. The probe itself sends stderr to
`/dev/null` — it has to, because "the user does not exist yet" is the normal state for most of the wait
— so without that, a failure explains nothing at all. A container killed by its `mem_limit` otherwise
looks exactly like one that is merely slow. Oracle's probe is a shell function rather than a one-liner,
because `sqlplus` takes its query on stdin.

`04` also sources `docker/.env`, so the passwords in the probes are not another copy of the literal.
That file is valid shell as well as a Compose env file, which is why that works.

### The setup owns WSL2, not your machine

**The setup installs into WSL2 and into this repository's working tree. It installs nothing on the
host and changes no host configuration.** WSL2 itself, PowerShell on Windows and the modules in
`modules.txt` are the user's to install. The alternative was a setup script that quietly ran
`Set-PSRepository -Name PSGallery -InstallationPolicy Trusted` on the machine of anyone who cloned the
repository — a decision that is not a demo repository's to make.

`00_check_host.ps1` is how that rule stays usable. It checks what the user has to provide, names
**every** missing piece at once with the command that installs it, and stops the setup. It changes
nothing, so it is safe to run at any time.

- **`00_check_host.ps1` has no dependencies, deliberately.** It runs before anything is guaranteed,
  so it imports no module and prints with `Write-Host` rather than `Write-PSFMessage` — PSFramework
  is one of the things it is checking for. Do not "fix" that inconsistency.
- **`03_pwsh_setup.ps1` runs twice and the two runs differ**, guarded by `if (-not $IsWindows)`. Inside
  WSL2 it installs the modules and downloads the drivers; on Windows it only downloads the drivers.
  It has **no `-Scope` parameter** — `AllUsers` is the only scope that was ever wanted, and it is what
  lets the PhotoService container mount `/usr/local/share/powershell/Modules`.
- **Downloading the drivers into `lib/` on Windows is not a breach of the rule.** `lib/` is inside the
  repository, not on the machine. Doing it at setup time also keeps a 40 MB download off the moment a
  demo is opened in front of an audience, and loading the driver afterwards is the only check the
  Windows side can make.

**It checks the default WSL2 distribution by starting it and asking Linux a question**
(`wsl -e uname -r`), not by parsing `wsl --list --verbose`. That output is UTF-16LE on Windows and
reading it is a well known trap; an answer that comes from inside the distribution has no such
problem, and it proves the thing that matters — that a default distribution exists and starts.

### Two setup improvements on the list, agreed and not done

Both are the owner's, both are low priority, and both apply to **this repository and the sibling** —
so do them on both sides in one turn. Do not treat either as a finding, and do not do them as a side
effect of an unrelated task.

1. **Timestamps in the step messages**, so that the actual timing of a run can be read off the output
   instead of guessed at.
2. **Quieten the noisy commands**, `apt-get` in `02_wsl2_setup.sh` above all, so that a run does not
   fill the terminal. Keep the failure output loud while doing it: `04_docker_compose.sh` prints
   `docker compose logs --tail 50` on its failure path precisely because a silent probe explains
   nothing, and that is the opposite trade from this one.

### Every step of `01_setup.ps1` announces itself

`Write-Step` prints a banner before each step, and the slow ones say roughly how long they take.
This exists because **a quiet stretch is indistinguishable from a hung script**: `04_docker_compose.sh`
is silent for about two minutes while it waits for Oracle. The Windows port wait prints one line per
port for the same reason — a forward that lags the others by minutes looks exactly like a hang.

`Write-Step` is defined inside `01_setup.ps1` and does not follow the `lib/` function contract,
which says so where it is defined.

### `01_setup.ps1` builds, `start_demo.ps1` runs

The two are deliberately separate, and the split is what lets **one WSL2 installation serve both
repositories**. Neither repository names a distribution — no `wsl` call anywhere passes `-d` — so both
use the default one.

- `01_setup.ps1` ends with `docker compose stop`. It builds the volumes, proves the connections from
  both sides, and leaves nothing running.
- `start_demo.ps1` starts a demo, holds the WSL2 shell open, and is what you run after a reboot or when
  switching repositories.
- `04_docker_compose.sh` **stops the sibling project's containers** before `docker compose up`, found by
  the `com.docker.compose.project` label so that no file from the other repository is needed. Both entry
  points call `04`, so both get it.

**Why stopping the other stack is not optional, and why a port conflict is the least of it.** Both
repositories publish the same ports *and* use the same password *and* create the same database names. A
bind error would at least be loud; instead the other stack answers every connection, so a run that
starts while the sibling's containers are up succeeds against the wrong volumes.

It is `docker stop`, never `down`: the other repository's volumes survive, so switching costs a minute
rather than another Oracle start. One cost of the split, known and not worth fixing: installing both
repositories pays for Oracle's first start twice, because the volumes are per compose project.

**Nothing after `04` should abort `01_setup.ps1` before the stop.** The Windows `06` records its failure
in a variable and throws after the containers are down; anything added there should do the same.

**But something has to hold WSL2 open while a Windows-only step runs, and that is not optional.** WSL2
terminates the distribution a few seconds after its last process exits, and every container goes with
it. As long as the setup is one `wsl` call after another that never happens; the Windows half of the
run is the first stretch during which no `wsl` process is alive. Measured once: the last WSL2 step
finished at 20:56:01, and at 20:56:16 every container logged a shutdown — postgres `received fast
shutdown request`, mongo a `SignalHandler` shutdown in the same second. `06_test_connections.ps1` on
Windows then failed with `Failed to connect to 127.0.0.1:5432`, which reads exactly like a missing port
forward and is nothing of the kind.

So `01_setup.ps1` starts a background `wsl sleep` before the port wait and stops it after
`docker compose stop`. Anything added between those two lines is covered by it. **Do not remove it
because the containers "are obviously still running" — that is the bug.**

### The port forwarding arrives late, and not for all ports at once

**Rule out the section above first.** A socket error from Windows has two candidate causes that look
identical from the driver's point of view: the forward is not there yet, or **the container is not
there any more** because WSL2 idled out. Check the container log before believing the port story —
`docker compose logs postgres` says `received fast shutdown request` in the one case and nothing at all
in the other. Container logs are in **UTC** while the PSFramework output is local time, which is what
makes the two look unrelated at a glance.

**A single connection failure from Windows is not evidence that a container is broken.** `127.0.0.1:1521`
is docker's published port inside WSL2 and a `wslrelay` listener on Windows, and the relay does not
publish every port at the same moment. On one clean install four forwards were up and 1521 was not —
which failed the check while Oracle was running and answering inside WSL2 the whole time. The error
names Oracle and means the network.

`01_setup.ps1` therefore waits for the four database ports and Redpanda to accept a connection from
Windows before it runs `06` there. The wait is silent and costs 0.1 s when the forwards are already up.
**Why one port lags the others is not established** — do not write down a mechanism for it without
evidence. `07_check_ports.ps1` is the diagnostic.

## Adding a dependency

`modules.txt` is the one list of PowerShell modules. It is read in two places and written in none:
`03_pwsh_setup.ps1` installs from it **inside WSL2**, and `00_check_host.ps1` reads the same file to
check the Windows side. The setup does not install modules on the host at all.

**Adding a module means adding a line to `modules.txt`. That is the whole procedure**, in the same turn
as the code that needs it. Then tell the owner to re-run `01_setup.ps1`: it installs the module inside
WSL2 and, on Windows, `00_check_host.ps1` names it as missing with the `Install-Module` line that
installs it. `README.md` prints the command rather than a list, so **do not reintroduce a second copy of
the module names anywhere**.

The ADO.NET drivers are not in that list: `Import-OraLibrary`, `Import-PgLibrary` and
`Import-KfkLibrary` download `Oracle.ManagedDataAccess.dll`, `Npgsql.dll` and `Confluent.Kafka.dll`
plus its native `librdkafka` from nuget.org into `lib/`. `03_pwsh_setup.ps1` calls all three, on both
sides, **before `04_docker_compose.sh` starts anything** — the photoservice container mounts `lib/`
read only, so it can load a driver but never download one. Those `*.dll` and `*.so` files are
gitignored — **never commit a DLL**.

## The sample data on disk

`data/` holds the inputs for the scenarios. Everything generated or downloaded is gitignored, so a fresh
clone has only the `README.md` files, `sample.json` and the PhotoService photos.

`05_sample_data_setup.ps1` creates or downloads the rest. The Excel files are rebuilt from `sample.json`
every run, which costs a second. **The four downloads are skipped when the files are already there** —
about 15 MB from three sites, most of it `countries.geojson`.
`pwsh ./05_sample_data_setup.ps1 -Force` fetches them again.

- The three Geodata artifacts are checked one at a time, so deleting one does not re-fetch the other
  two. The StackExchange check is "are there any `*.xml`", which is coarse on purpose: a half-extracted
  archive is not a state worth modelling in a setup script, and `-Force` is the answer to it.
- Downloads go to `<name>.part` and are renamed only once the size matches `Content-Length`, so a
  download cut off halfway cannot leave a file that looks good and fails much later inside a demo.
- `05` extracts the archives with `7za`, which exists in WSL2. On Windows the equivalent is
  `C:\Program Files\7-Zip\7z.exe`, which the script calls by its short path because it is not on the
  PATH. When the data is already there, every download is skipped and neither is reached.

`countries.geojson` should be about **14.6 MB / 258 features**, which is the quickest way to confirm the
file by hand. It is the whole world and not only the EU; the filter that would reduce it is commented
out in `05` on purpose.

## Repository map

| Path | What it is |
| --- | --- |
| `00_check_host.ps1` | Checks that this machine has what the setup will not install: PowerShell 7.5, the modules in `modules.txt`, and a WSL2 default distribution with `apt-get`. Names every missing piece at once with the command that fixes it, and changes nothing. `01_setup.ps1` runs it first; it is also safe to run alone. |
| `01_setup.ps1` … `06_test_connections.ps1` | One-time setup, started from Windows, shells into WSL2. `01_setup.ps1` orchestrates the rest. It **builds only** — it stops the containers again at the end. |
| `07_check_ports.ps1` | **Not part of the setup sequence.** A read-only diagnostic for when the Windows half cannot reach a database: per published port, whether Windows has a `wslrelay` listener and whether a connection gets through. |
| `modules.txt` | The one list of PowerShell modules. Both installs read it; nothing else enumerates them. |
| `start_demo.ps1` | Starts the demo: stops the sibling repository's containers, starts this repository's, and holds WSL2 open. `01_setup.ps1` builds, this runs. |
| `data/<scenario>/` | Sample data per scenario. Generated and downloaded artifacts are gitignored; only `README.md` and `sample.json` (plus the photos) are committed. |
| `demo/` | The six numbered demo scripts plus the per-scenario `init_*.ps1` connection bootstraps. |
| `docker/` | `docker-compose.yaml`, the per-scenario database init SQL/sh/js, and the PhotoService application. |
| `lib/` | 41 dot-sourced functions — the data access layer. The `*.dll` files are downloaded, not committed. |
| `verify/` | The known-good numbers as runnable scripts, one per scenario, plus `Invoke-Verify.ps1` and `Verify-Common.ps1`. Needs the containers up. **Not a test suite** — see `verify/README.md`. |
| `SIBLING-FINDINGS.md` | The cross-repository work queue. Currently empty. |

## The lib/ naming grid

Every function is `<Verb>-<Prefix><Noun>`. The prefixes are `Sql` (SQL Server), `Ora` (Oracle),
`Pg` (PostgreSQL), `Mdb` (MongoDB), `Kfk` (Kafka) and `Mio` (MinIO, kept but no longer in the lab). The
verb families are:

| Family | Purpose |
| --- | --- |
| `Connect-*Instance` | Open a connection (MinIO returns a `PSCustomObject` with script methods instead). |
| `Invoke-*Query` | Run a query and return the whole result in memory. |
| `Read-*Query`, `Read-MdbCollection`, `Read-KfkTopic` | Run a query and stream the result row by row. |
| `Get-*DataReader` | Return an open `DbDataReader` for streaming into a `Write-*Table`. |
| `Write-*Table`, `Write-MdbCollection`, `Write-KfkTopic` | Bulk-load objects or a data reader into a table. |
| `Import-*Table` / `Export-*Table` | File to table and table to file. |
| `Get-*TableInformation` | Column metadata for a table. |
| `Import-OraLibrary` / `Import-PgLibrary` / `Import-KfkLibrary` | Download and load the driver DLLs from nuget.org. |
| `Get-MioFile`, `Get-MioFileList`, `Set-MioFile`, `Remove-MioFile` | Object storage operations. |

**Sibling rule:** the `Sql`, `Ora` and `Pg` implementations of a verb family are near-identical by
design. Before changing `lib/Xxx-SqlYyy.ps1`, read `Xxx-OraYyy.ps1` and `Xxx-PgYyy.ps1`. Either apply
the same change to all siblings, or say explicitly why that provider has to differ. Unexplained
divergence between siblings is a bug. **This rule also reaches across repositories:** if the Python
function has a parameter or a guard clause and this one does not, that is a finding unless the
difference is inherent to the language.

`lib/README.md` has the full index, including which cells of the grid are deliberately empty.

## Function contract

```powershell
function Verb-PrefixNoun {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][string]$Table,
        [int]$BatchSize = 1000,
        [switch]$EnableException
    )
    ...
}
```

- `[CmdletBinding()]`, and `[OutputType()]` where the output type is worth stating.
- Parameter attributes are compressed onto one line: `[Parameter(Mandatory)][string]$Instance`.
- **Every function ends its param block with `[switch]$EnableException`.** Callers opt in with
  `$PSDefaultParameterValues = @{ "*-Sql*:EnableException" = $true }`.
- Errors always go through PSFramework, never `throw`:

  ```powershell
  } catch {
      Stop-PSFFunction -Message "<Step> failed: $($_.Exception.InnerException.Message)" -Target $command -EnableException $EnableException
      return
  }
  ```

  The `return` matters — without it execution continues into code that assumes the failed step worked.

  `InnerException` is deliberate and correct **when the try block fails inside a .NET method call**:
  PowerShell wraps those in a `MethodInvocationException`, so the useful message is one level down.
  It is **wrong when the try block only calls PowerShell cmdlets** (`Invoke-WebRequest`, `Connect-Mdbc`,
  `Move-Item`, …) — there is no wrapper, `InnerException` is null, and the message renders as
  `"<Step> failed: "` with no cause at all. Use `$($_.Exception.Message)` in those functions.
- The message names the step. A placeholder is the message for the failure mode that is hardest to
  debug.
- `finally` blocks dispose commands, readers and streams.
- Logging is `Write-PSFMessage -Level Verbose` inside `lib/` and `-Level Host` in the setup and init
  scripts. **No `Write-Host` or `Write-Verbose` in `lib/`.** Demo scripts may use `Write-Host`.
- Long-running bulk operations report with `Write-Progress -Id 1`.
- Runnable scripts start with `$ErrorActionPreference = 'Stop'` and may `throw`. The contract above is
  for `lib/`; a helper defined inside a setup script does not follow it, and says so where it is
  defined.

## Loading model

There is **no module manifest and no `.psm1` — that is deliberate**, so the audience can see plain
functions in plain files. Functions are loaded by dot-sourcing:

```powershell
Import-Module -Name PSFramework
foreach ($file in (Get-ChildItem -Path ../lib/*-*.ps1)) { . $file.FullName }
```

`Import-Module PSFramework` has to come first, because every `lib/` function calls `Write-PSFMessage`
and `Stop-PSFFunction`. `lib/*.dll` and `lib/*.so` are downloaded by `03_pwsh_setup.ps1` and are
gitignored. Required modules are in `modules.txt` — see `Adding a dependency` above, and do not copy
the list back into this file.

## Deliberate decisions — do not "fix" these

- The password `Passw0rd!` is hard-coded in `docker/.env`, the init SQL, the demos and the setup
  scripts. These are throwaway local containers and the password being visible is part of the teaching.
  It is not a security finding. Do not parameterize it, do not move it to a vault.
- **`docker/.env` is not the single source of it, and the README says so.** `sqlserver-init.sh` and
  `04_docker_compose.sh` read it from the environment, but the `CREATE USER` statements in the init SQL
  still hold it as a literal — deliberately, because making those interpolate needs an entrypoint that
  rewrites SQL, and a visible `CREATE USER … 'Passw0rd!'` on a slide says what it does.
- `ConvertTo-SecureString -AsPlainText -Force` — same reason.
- `127.0.0.1` rather than `localhost`, to force IPv4.
- **The shop stores local time, and `- /etc/localtime:/etc/localtime:ro` on the `photoservice`
  service is what makes that true.** UTC would be the better default anywhere else; here the demo is
  read off a wall clock, and an order placed at 18:23 that pgAdmin shows as 16:23 costs a minute of
  explaining that has nothing to do with moving data. The image has **no time zone data at all**, so
  without that mount "local" is UTC and `TZ` on its own does nothing. The sibling's compose file mounts
  the same file for the same reason. Do not remove the mount, and do not replace it with a `TZ`
  variable.
- **`Get-LocalTimestamp` in `docker/photoservice-app.ps1` exists because of Npgsql**, which turns a
  `DateTime` whose `Kind` is `Local` into UTC on the way into a `TIMESTAMP` column. `Unspecified` is
  what that column actually is — a wall clock with no zone — and it keeps the value the application
  put on the Kafka topic identical to the value in the database.
- **dbatools is deliberately not used.** Hand-written ADO.NET *is* the demo. Never propose replacing it.
- `System.Data.SqlClient` rather than `Microsoft.Data.SqlClient` — a known and accepted trade-off,
  because the legacy client ships with .NET and needs no extra download.
- No Pester tests, no CI, no module manifest, no `ShouldProcess`/`-WhatIf` on state-changing verbs.
- No comment-based help in `lib/`. Twenty lines of header before the interesting code hurts the demo;
  `lib/README.md` carries that information instead.

## Verifying a change

The containers are probably not running, and starting them costs a WSL2 boot and several minutes.

**Whether an agent may drive the lab is a per-machine decision**, because it depends on whether that
WSL2 installation is disposable. It is recorded in `.claude/settings.local.json`, which is **not**
committed — do not put it in the shared `settings.json`, which would grant it on the machine of
everyone who clones this repository. **If your `settings.local.json` does not grant it, the containers
are off limits** — verify statically and say so, rather than starting anything.

Where it is granted, two limits remain:

- **`wsl --unregister` needs the owner**, because putting the distribution back needs an elevated
  session. It stays denied even on the owner's machine.
- **`docker compose down -v` needs asking first.** It costs about two minutes, not the quarter of an
  hour it is sometimes assumed to — the Oracle image ships a prebuilt database. So the cost is not
  time, it is **whatever state somebody has not saved**: a demo half stepped through, a table being
  looked at, photos loaded into PostgreSQL by demo 4. Ask, and say what will go. `docker compose stop`
  is the right thing for merely switching repositories.

**One consequence worth taking advantage of.** The init SQL under `docker/` only runs on empty volumes.
Rebuilding is cheap, so **edit the init SQL and rebuild instead of writing a migration**, unless the
volumes hold something worth keeping.

**Hold WSL2 open before you start anything, and keep holding it.** WSL2 terminates the distribution a
few seconds after its last process exits, and every container goes with it — so a stack started by one
tool call is gone before the next one runs. Start a detached keepalive first and leave it running:

```powershell
$p = Start-Process -FilePath wsl -ArgumentList 'sleep', '36000' -PassThru -WindowStyle Hidden
```

**Do not run `start_demo.ps1` itself.** Its last line is an interactive `wsl` shell whose only job is to
be that keepalive, and it will hang a non-interactive session. Run `04_docker_compose.sh` directly
instead — it is the part that does the work:

```powershell
wsl --cd $repositoryRoot --user root ./04_docker_compose.sh
```

Demo scripts are still **never run end to end** — the `break` on line 1 stays. Running a *selected
section* against live containers is fine and is how a demo gets tested. `07_check_ports.ps1` is safe at
any time.

Static checks are worth running first, because they cost nothing:

```powershell
# Syntax check
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
$errors

# Style and rule check
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Read-only inspection (`docker ps`, `docker compose logs`, `git`) is fine. Note that `docker` lives
inside WSL2 and is **not** on the Windows PATH, so reaching it would mean running `wsl` — ask the owner
about container state instead of starting anything.

### But static checks are not enough

Every real defect the sibling repository found in this one was found by **running code against the live
containers** — never by reading it. Parsing and PSScriptAnalyzer were green every time. The failures
that matter here are quiet: a timestamp that loses its milliseconds, an import that fills every column
with `NULL` and reports the right number of rows, a bulk load that lands 187 of 258 rows.

So when the containers are up and the owner has said it is allowed:

- **Compare values against the source, column by column. A row count is not a check.** The worst bug in
  the sibling reported `OK - 12220 rows in 0.27 s` while discarding the milliseconds of every timestamp,
  and checking one column would have confirmed it as correct, because that column's values all end in
  `.000`.
- **Do not trust a passing check that could have got lucky.** `FETCH FIRST 3 ROWS ONLY` reported an
  Oracle geometry read-back as working; over the whole table it fails for a fifth of the rows.
- Drive the shipped `lib/` functions rather than reimplementing their logic in the test, create and drop
  your own tables, and print `PASS`/`FAIL` per check.
- **Before believing a `PASS`, ask what the check would print if the thing under test were absent.**
  A check that compares failure *counts* while the membership moves, a check that compares MD5 hashes
  that are `NULL` on both sides, and a check that asserts a row count copied out of the documentation
  rather than out of the data all read as green. Assert the preconditions too — that the source is
  non-`NULL`, that the column has real values in it — or the comparison is measuring nothing.

If a change really cannot be verified — containers down, driver missing — say so plainly rather than
claiming it works.

#### `verify/` is these numbers, made runnable — start there

The table below exists as scripts. **Run those instead of writing new ones**, and add to them rather
than starting again in a scratchpad:

```powershell
.\verify\Invoke-Verify.ps1              # all six, ten to fifteen minutes
.\verify\Invoke-Verify.ps1 -Only 06     # one scenario
```

97 checks over the six scenarios. `verify/README.md` says what each script covers, what it changes, and
why two numbers are printed rather than asserted. It is **not** a test suite: no Pester, no CI, no
fixtures, and `01_setup.ps1` does not call it. A throwaway check takes its bugs with it, which is the
argument for the folder.

#### Known-good numbers

Reproduce these rather than inventing a new check. Both repositories were driven through their own
shipped functions and agreed on every one:

| What | Number |
| --- | --- |
| `Users.xml` | 12220 rows; **12179** carry real milliseconds in `LastAccessDate`, while **all 12220** `CreationDate` values end in `.000` — which is why that column alone proves nothing |
| StackExchange import | 0 of 12220 differ on either timestamp column, on SQL Server, PostgreSQL and Oracle, **with no tolerance** |
| Timesheets | **94** rows from the three `Department*.xlsx`, 3 departments, 4 people |
| `countries.geojson` | 14643643 bytes, **258** features; PostGIS converts 258/258 with 0 invalid |
| Oracle `TO_WKTGEOMETRY` | non-deterministic on purpose — seen at 26, 31, 39, 40, 42 and 64 failures over the same 258 rows. **Do not "fix" this or write down a mechanism**; the sibling's `DIFFERENCES.md` has four rejected explanations. `verify/03_geodata.ps1` prints the count and deliberately does not assert it |
| ProjectStatus | 9 rows after blanks are dropped, **8** after the `NEW PROJECTS:` heading is skipped, 4 rejected for 4 distinct reasons, 5 land after the colour retry, 3 handed back |
| PhotoService photos | **24** images, **43.5 MB**, byte-identical by MD5 and length — and check they are not `NULL` first, because the `photo` rows exist with a `NULL` image until demo 4's first section loads them |
| PhotoService transfer | first pass ~3.5 s, later passes ~0.37 s; the watermarks in the log are the point |

## Style

Four-space indentation, K&R braces (`} else {`), single quotes unless interpolating, `$null =` to
suppress output, splatting for calls with many parameters, and `=` aligned inside hashtables:

```powershell
$invokeParams = @{
    Connection = $connection
    Table      = 'dbo.Timesheets'
    BatchSize  = 10000
}
Write-SqlTable @invokeParams
```

`[PSCustomObject]` arrays are the canonical in-memory shape for data in flight.

**Do not reformat lines you are not otherwise changing.** That is about wrapping, quoting and moving
code around, not about whitespace — every tracked file outside `data/` is clean of trailing whitespace
and ends with a newline, and `.editorconfig` sets `trim_trailing_whitespace` and `insert_final_newline`
to keep it that way. So a stray trailing space in a diff is something you introduced.

## Adding or changing a demo scenario

A scenario touches all of these. Miss one and the repository is inconsistent.

1. `data/<name>/README.md` and, if the data is generated, `data/<name>/sample.json`
2. The generated or downloaded artifact pattern in `.gitignore`
3. The scenario block in `05_sample_data_setup.ps1`
4. `docker/sqlserver-<name>.sql` (and the Oracle/Postgres equivalent if used), plus the mount in
   `docker/docker-compose.yaml` and the line in `docker/sqlserver-init.sh`. If it is created last
   there, it is also what `04_docker_compose.sh` waits for
5. `demo/NN_<name>.ps1`, starting with `break`
6. `demo/init_<name>.ps1` if the scenario needs more than one connection
7. The connection check in `06_test_connections.ps1` if a new database or user is involved
8. **The `### <Name>` section under "Demo scenarios" in `README.md`**
