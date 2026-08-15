# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this repository is

A teaching and demo repository that accompanies talks and videos: infrastructure as code, sample data
and demo code showing how PowerShell can move data around. It is deliberately **not production code**
(see `README.md`).

It has a sibling: [Python moves Data around](https://github.com/andreasjordan/Python-moves-Data-around),
which is a port of this repository, scenario by scenario. The two are presented **side by side in one
session**, so a change here is also a change to one half of a comparison. That has three consequences
worth knowing before touching anything:

- The Python repository is the one that has been driven against live containers most recently, and it
  found real defects in this one. Its `SIBLING-FINDINGS.md` is the work list for a session opened here.
- **When something is wrong in the sibling repository and you cannot reach it, append an entry to
  `SIBLING-FINDINGS.md` here** rather than fixing it there. That is the rule for a session opened in
  this repository alone, which is the usual case. **If both repositories are open** — a VS Code
  workspace holding the two of them, so the Python repository is a working directory and not just a
  path — then fix it in place instead, and commit per repository. `SIBLING-FINDINGS.md` is then the
  queue for what is deliberately deferred, not a way of routing work across a wall. Say which of the
  two situations you are in before the first change on the other side.
- The sibling keeps the reasoning behind every place the two differ in its `DIFFERENCES.md`. When a
  change here would make a documented difference wrong, say so — nobody on the other side will notice
  on their own.

**Prime directive:** optimize every change for *readability while being shown on a projector*, not for
robustness, genericity or production hardening. If a change makes the code shorter and clearer, it is
probably right. If it adds abstraction, indirection or defensive layers, it is probably wrong.

## Current state — read this before assuming anything works

All five scenarios work and have been presented. What follows is what is *known* and unfinished, so
that it is not rediscovered as a new finding and not fixed as a side effect of an unrelated task.

| Area | State |
| --- | --- |
| `demo/01_timesheets.ps1` … `05_projectstatus.ps1` | Complete. Stepped through section by section, never run. |
| `lib/` | 35 functions. The grid in `lib/README.md` says which cells are deliberately empty. |
| The setup chain | `01_setup.ps1` **builds only** — it stops the containers at the end, so it can be run in this repository and then in the sibling, in either order. `start_demo.ps1` is what starts a demo. See "01_setup.ps1 builds, start_demo.ps1 runs" below. |
| `06_test_connections.ps1` | Run **twice** by `01_setup.ps1`: once inside WSL2 and once on Windows, because the demos run from Windows and nothing else checks that side. One block per scenario and per provider. |
| MinIO | **Scheduled to be removed**, entry 9 of `SIBLING-FINDINGS.md`. It changed its licence, and uploading files is a different question from the one every other provider here answers. Do not build anything new on it. The hand-rolled AWS SigV4 signing in `Connect-MioInstance` is the most interesting code in either repository and is worth keeping somewhere outside the demo before it goes. |
| Event streaming | The PhotoService demo's *"Transfer data from logging (or kafka)"* section reads the application's log archives out of MinIO. The sibling has replaced that with a real Kafka demo served by Redpanda; porting it back here is entry 10 of `SIBLING-FINDINGS.md`, including four things learned the hard way over there. |
| `lib/Write-PgTable.ps1` | Fills a `DataTable` and lets an `NpgsqlDataAdapter` generate the `INSERT` statements. PostgreSQL's own bulk path, `COPY`, is not used, and the sibling measured that at 7× slower. A long-standing wish rather than a defect — entry 3 of `SIBLING-FINDINGS.md`. |
| `docker/photoservice-app.ps1` | The shop that keeps inventing customers and orders. **It is the source of everything the second half of demo 04 transfers**, so those cells have nothing to find unless this container is running — and it staggers its work over twenty minutes after it starts. `docker compose restart photoservice` is the cheap reset, and it restarts that clock. |
| The Azure SQL bonus sections | At the end of `demo/02_stackexchange.ps1` and `demo/04_photoservice.ps1`. They need Azure resources, the `Az` module, a firewall rule and two environment variables, so they are not local and are not part of a normal run. |

## Demo scripts are stepped through, never run

`demo/01_timesheets.ps1`, `02_stackexchange.ps1`, `03_geodata.ps1`, `04_photoservice.ps1` and
`05_projectstatus.ps1` all begin with a bare `break` on line 1. That is deliberate: the file is opened in
VS Code and executed section by section (F8 on a selection), telling a story as it goes.

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

## The setup chain, and what is load-bearing in it

Three things in `04_docker_compose.sh` exist because the failure each one prevents is silent or
misleading. Do not simplify them away.

**It waits for the demo databases, not for the server.** The databases are created after the server
starts accepting connections, so a check that only asks "does it answer" returns too early. There is no
such failure today and that is an accident: `05_sample_data_setup.ps1` used to spend minutes downloading
sample data, which always gave the containers enough time. Skipping downloads that are already there
takes that accidental wait away, which is why the two changes belong together.

**Do not wait by grepping the container log** for the init script's `SQL Server configuration complete.`
message. `docker logs` keeps the output of earlier runs, so on a restarted container it matches
immediately — measured at one second in the sibling, while the server was still starting. It looks like
a fix and silently keeps the race. Query `sys.databases` instead.

**It waits for the docker daemon first.** `02_wsl2_setup.sh` starts docker, but `01_setup.ps1` then runs
`wsl --shutdown`, and `start_demo.ps1` runs after a reboot — so in both cases the daemon has to come up
again, and it only does because systemd starts it. That is a race right after WSL2 boots.

**`wait_for` gives up when the container has stopped**, instead of sitting out the full 5 or 15 minutes,
and the failure path prints `docker compose logs --tail 50`. The probe itself sends stderr to
`/dev/null` — it has to, because "the user does not exist yet" is the normal state for most of the wait
— so without that, a failure explains nothing at all. A container killed by its `mem_limit` otherwise
looks exactly like one that is merely slow. Oracle gets 15 minutes rather than 5, and its probe is a
shell function rather than a one-liner, because `sqlplus` takes its query on stdin.

`04` also sources `docker/.env`, so the passwords in the probes are not another copy of the literal.
That file is valid shell as well as a Compose env file, which is why that works.

### `01_setup.ps1` builds, `start_demo.ps1` runs

The two are deliberately separate, and the split is what lets **one WSL2 installation serve both
repositories**. Neither repository names a distribution — no `wsl` call anywhere passes `-d` — so both
have always used the default one.

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
rather than another Oracle start.

**Two costs of the split, both known and neither worth fixing:** installing both repositories pays for
Oracle's first start twice, because the volumes are per compose project; and switching restarts the
PhotoService container, which truncates its tables and restarts its twenty-minute clock. Until that
schedule is shortened, put the PhotoService demo last on each side and switch once.

**Nothing after `04` should abort `01_setup.ps1` before the stop.** The Windows `06` records its failure
in a variable and throws after the containers are down; anything added there should do the same. This
used to be the most expensive rule in the repository, because the last line was the `wsl` shell that
kept the containers alive — the split defused it, and it is housekeeping now rather than a trap.

**But something has to hold WSL2 open while a Windows-only step runs, and that is not optional.** WSL2
terminates the distribution a few seconds after its last process exits, and every container goes with
it. As long as the setup was one `wsl` call after another that never came up; the Windows half of `12`
is the first stretch of this script during which no `wsl` process is alive.

Measured the first time that half ran: the last WSL2 step finished at 20:56:01, and at **20:56:16 every
container logged a shutdown** — postgres `received fast shutdown request`, mongo a `SignalHandler`
shutdown in the same second. `06_test_connections.ps1` on Windows was two connections into its run and
failed on the next one with `Failed to connect to 127.0.0.1:5432`, which reads exactly like a missing
port forward and is nothing of the kind.

So `01_setup.ps1` starts a background `wsl sleep` before the port wait and stops it after
`docker compose stop`. Anything added between those two lines is covered by it; anything added *after*
the stop is not, and does not need to be. **Do not remove it because the containers "are obviously
still running" — that is the bug.**

### The port forwarding arrives late, and not for all ports at once

**Rule out the section above first.** A socket error from Windows has two candidate causes that look
identical from the driver's point of view: the forward is not there yet, or **the container is not
there any more** because WSL2 idled out. Check the container log before believing the port story —
`docker compose logs postgres` says `received fast shutdown request` in the one case and nothing at all
in the other. Note that container logs are in **UTC** while the PSFramework output is local time, which
is what makes the two look unrelated at a glance.

**A single connection failure from Windows is not evidence that a container is broken.** `127.0.0.1:1521`
is docker's published port inside WSL2 and a `wslrelay` listener on Windows, and the relay does not
publish every port at the same moment. In the sibling repository, on a clean install, four forwards were
up and 1521 was not — which failed the check while Oracle was running and answering inside WSL2 the
whole time. The error names Oracle and means the network.

`01_setup.ps1` therefore waits for the four database ports and MinIO to accept a connection from Windows before it
runs `06` there. The wait is silent and costs 0.1 s when the forwards are already up. **Why one port
lags the others is not established** — do not write down a mechanism for it without evidence.
`07_check_ports.ps1` is the diagnostic that settled it over there, and it is in this repository for the
same reason.

## Adding a dependency

`modules.txt` is the one list of PowerShell modules. `03_pwsh_setup.ps1` installs it, and
`01_setup.ps1` runs that script **twice** — `-Scope CurrentUser` on Windows and `-Scope AllUsers` inside
WSL2, where `AllUsers` puts them in `/usr/local/share/powershell/Modules` so that the PhotoService
container can mount them.

**Adding a module means adding a line to `modules.txt`. That is the whole procedure**, in the same turn
as the code that needs it. Then tell the owner to re-run `01_setup.ps1`, which is what installs it on
both sides. `README.md` prints the command rather than a list, so **do not reintroduce a second copy of
the module names anywhere** — the sibling had exactly that and its two lists drifted twice.

The ADO.NET drivers are not in that list: `Import-OraLibrary` and `Import-PgLibrary` download
`Oracle.ManagedDataAccess.dll` and `Npgsql.dll` from nuget.org into `lib/` on first use. Those `*.dll`
files are gitignored — **never commit a DLL**.

## The sample data on disk

`data/` holds the inputs for the scenarios. Everything generated or downloaded is gitignored, so a fresh
clone has only the `README.md` files, `sample.json` and the PhotoService photos.

`05_sample_data_setup.ps1` creates or downloads the rest. The Excel files are rebuilt from `sample.json`
every run, which costs a second. **The four downloads are skipped when the files are already there** —
about 15 MB from three sites, most of it `countries.geojson`.
`pwsh ./05_sample_data_setup.ps1 -Force` fetches them again.

Two practical notes for an agent that needs the data present:

- The three Geodata artifacts are checked one at a time, so deleting one does not re-fetch the other
  two. The StackExchange check is "are there any `*.xml`", which is coarse on purpose: a half-extracted
  archive is not a state worth modelling in a setup script, and `-Force` is the answer to it.
- `05` extracts the archives with `7za`, which exists in WSL2. On Windows the equivalent is
  `C:\Program Files\7-Zip\7z.exe`, which the script calls by its short path because it is not on the
  PATH. When the data is already there, every download is skipped and neither is reached.

`countries.geojson` should be about **14.6 MB / 258 features**, which is the quickest way to confirm the
file by hand. It is the whole world and not only the EU; the filter that would reduce it is commented
out in `05` on purpose.

## Repository map

| Path | What it is |
| --- | --- |
| `01_setup.ps1` … `06_test_connections.ps1` | One-time setup, started from Windows, shells into WSL2. `01_setup.ps1` orchestrates the rest. It **builds only** — it stops the containers again at the end. |
| `07_check_ports.ps1` | **Not part of the setup sequence.** A read-only diagnostic for when the Windows half cannot reach a database: per published port, whether Windows has a `wslrelay` listener and whether a connection gets through. |
| `modules.txt` | The one list of PowerShell modules. Both installs read it; nothing else enumerates them. |
| `start_demo.ps1` | Starts the demo: stops the sibling repository's containers, starts this repository's, and holds WSL2 open. `01_setup.ps1` builds, this runs. |
| `data/<scenario>/` | Sample data per scenario. Generated and downloaded artifacts are gitignored; only `README.md` and `sample.json` (plus the photos) are committed. |
| `demo/` | The five numbered demo scripts plus the per-scenario `init_*.ps1` connection bootstraps. |
| `docker/` | `docker-compose.yaml`, the per-scenario database init SQL/sh/js, and the PhotoService application. |
| `lib/` | 35 dot-sourced functions — the data access layer. The `*.dll` files are downloaded, not committed. |
| `SIBLING-FINDINGS.md` | Work for the Python repository, written down on this side. Not a defect list for this one. |

## The lib/ naming grid

Every function is `<Verb>-<Prefix><Noun>`. The prefixes are `Sql` (SQL Server), `Ora` (Oracle),
`Pg` (PostgreSQL), `Mdb` (MongoDB) and `Mio` (MinIO). The verb families are:

| Family | Purpose |
| --- | --- |
| `Connect-*Instance` | Open a connection (MinIO returns a `PSCustomObject` with script methods instead). |
| `Invoke-*Query` | Run a query and return the whole result in memory. |
| `Read-*Query`, `Read-MdbCollection` | Run a query and stream the result row by row. |
| `Get-*DataReader` | Return an open `DbDataReader` for streaming into a `Write-*Table`. |
| `Write-*Table`, `Write-MdbCollection` | Bulk-load objects or a data reader into a table. |
| `Import-*Table` / `Export-*Table` | File to table and table to file. |
| `Get-*TableInformation` | Column metadata for a table. |
| `Import-OraLibrary` / `Import-PgLibrary` | Download and load the ADO.NET driver DLLs from nuget.org. |
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
- The message names the step. A placeholder shipped once — `"???? failed: …"` in `Write-PgTable` — and
  it was the message for the failure mode that is hardest to debug.
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
and `Stop-PSFFunction`. `lib/*.dll` are downloaded from nuget.org on first use by `Import-OraLibrary` /
`Import-PgLibrary` and are gitignored.

Required modules are in `modules.txt` — see `Adding a dependency` above, and do not copy the list back
into this file.

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
- **dbatools is deliberately not used.** Hand-written ADO.NET *is* the demo. Never propose replacing it.
- `System.Data.SqlClient` rather than `Microsoft.Data.SqlClient` — a known and accepted trade-off,
  because the legacy client ships with .NET and needs no extra download.
- No Pester tests, no CI, no module manifest, no `ShouldProcess`/`-WhatIf` on state-changing verbs.
- No comment-based help in `lib/`. Twenty lines of header before the interesting code hurts the demo;
  `lib/README.md` carries that information instead.

## Verifying a change

The containers are probably not running, and starting them costs a WSL2 boot and several minutes.

**Do not run** `wsl`, `docker compose up`/`down`, `01_setup.ps1`, `start_demo.ps1` or any script in
`demo/`. **`docker compose down -v` in particular is a twenty-minute mistake** — the `-v` deletes the
volumes, and getting them back means another Oracle start. Recommend it, never run it.
`07_check_ports.ps1` **is** safe to run. Verify statically otherwise:

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

### But static checks are not enough, and that is the lesson of the port

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

If a change really cannot be verified — containers down, driver missing — say so plainly rather than
claiming it works.

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
to keep it that way. So a stray trailing space in a diff is now something you introduced.

## Adding or changing a demo scenario

A scenario touches all of these. Miss one and the repository is inconsistent — this checklist exists
because the ProjectStatus demo shipped without its `README.md` section, and without its block in
`06_test_connections.ps1`.

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
