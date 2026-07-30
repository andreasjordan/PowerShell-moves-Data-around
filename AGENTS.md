# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this repository is

A teaching and demo repository that accompanies talks and videos: infrastructure as code, sample data
and demo code showing how PowerShell can move data around. It is deliberately **not production code**
(see `README.md`).

**Prime directive:** optimize every change for *readability while being shown on a projector*, not for
robustness, genericity or production hardening. If a change makes the code shorter and clearer, it is
probably right. If it adds abstraction, indirection or defensive layers, it is probably wrong.

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

Scripts that *are* meant to run: the numbered scripts in the repository root, `start_containers.ps1`,
`demo/init_*.ps1`, and `demo/04_photoservice_transfer_01.ps1`. `demo/Import-GpxFile.ps1` and
`demo/Import-XlsTimesheet.ps1` only define a function and are dot-sourced.

## Repository map

| Path | What it is |
| --- | --- |
| `01_setup.ps1` … `06_test_connections.ps1` | One-time setup, started from Windows, shells into WSL2. `01_setup.ps1` orchestrates the rest. |
| `start_containers.ps1` | Restarts the Docker containers after a reboot. |
| `data/<scenario>/` | Sample data per scenario. Generated and downloaded artifacts are gitignored; only `README.md` and `sample.json` (plus the photos) are committed. |
| `demo/` | The five numbered demo scripts plus the per-scenario `init_*.ps1` connection bootstraps. |
| `docker/` | `docker-compose.yaml`, the per-scenario database init SQL/sh/js, and the PhotoService application. |
| `lib/` | 35 dot-sourced functions — the data access layer. The `*.dll` files are downloaded, not committed. |

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
divergence between siblings is a bug.

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
- `finally` blocks dispose commands, readers and streams.
- Logging is `Write-PSFMessage -Level Verbose` inside `lib/` and `-Level Host` in the setup and init
  scripts. **No `Write-Host` or `Write-Verbose` in `lib/`.** Demo scripts may use `Write-Host`.
- Long-running bulk operations report with `Write-Progress -Id 1`.
- Runnable scripts start with `$ErrorActionPreference = 'Stop'`.

## Loading model

There is **no module manifest and no `.psm1` — that is deliberate**, so the audience can see plain
functions in plain files. Functions are loaded by dot-sourcing:

```powershell
Import-Module -Name PSFramework
foreach ($file in (Get-ChildItem -Path ../lib/*-*.ps1)) { . $file.FullName }
```

`Import-Module PSFramework` has to come first, because every `lib/` function calls `Write-PSFMessage`
and `Stop-PSFFunction`. `lib/*.dll` are downloaded from nuget.org on first use by `Import-OraLibrary` /
`Import-PgLibrary` and are gitignored — **never commit a DLL**.

Required modules: `PSFramework`, `ImportExcel`, `Mdbc`, `Microsoft.PowerShell.ConsoleGuiTools`.

## Deliberate decisions — do not "fix" these

- The password `Passw0rd!` is hard-coded in `docker/.env`, the init SQL, the demos and the setup
  scripts. These are throwaway local containers and the password being visible is part of the teaching.
  It is not a security finding. Do not parameterize it, do not move it to a vault.
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

**Do not run** `wsl`, `docker compose up`/`down`, `01_setup.ps1`, `start_containers.ps1` or any script
in `demo/`. Verify statically instead:

```powershell
# Syntax check
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
$errors

# Style and rule check
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Read-only inspection (`docker ps`, `docker compose logs`, `git`) is fine.

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

**Do not reformat lines you are not otherwise changing.** There is pre-existing trailing whitespace in
places; leave it alone unless the task is explicitly a formatting pass.

## Adding or changing a demo scenario

A scenario touches all of these. Miss one and the repository is inconsistent — this checklist exists
because the ProjectStatus demo shipped without its `README.md` section.

1. `data/<name>/README.md` and, if the data is generated, `data/<name>/sample.json`
2. The generated or downloaded artifact pattern in `.gitignore`
3. The scenario block in `05_sample_data_setup.ps1`
4. `docker/sqlserver-<name>.sql` (and the Oracle/Postgres equivalent if used), plus the mount in
   `docker/docker-compose.yaml` and the line in `docker/sqlserver-init.sh`
5. `demo/NN_<name>.ps1`, starting with `break`
6. `demo/init_<name>.ps1` if the scenario needs more than one connection
7. The connection check in `06_test_connections.ps1` if a new database or user is involved
8. **The `### <Name>` section under "Demo scenarios" in `README.md`**
