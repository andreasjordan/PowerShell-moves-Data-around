# lib/ — the data access layer

These 35 functions are the plumbing the demos build on. They are plain functions in plain files, loaded
by dot-sourcing rather than by a module, so that a demo can show exactly which code is being called:

```powershell
Import-Module -Name PSFramework
foreach ($file in (Get-ChildItem -Path ../lib/*-*.ps1)) { . $file.FullName }
```

`Import-Module PSFramework` has to come first — every function logs through `Write-PSFMessage` and
reports errors through `Stop-PSFFunction`. The Oracle and PostgreSQL functions additionally need
`Import-OraLibrary` / `Import-PgLibrary`, which download the ADO.NET drivers from nuget.org into this
directory on first use. Those `*.dll` files are gitignored.

## How the pieces fit together

**Moving data between two database systems without materializing it in memory** is the point of the
library. Open a connection to each side, get a data reader from the source, hand it to the writer on the
target:

```powershell
$reader = Get-SqlDataReader -Connection $sourceConnection -Table dbo.Posts
Write-PgTable -Connection $targetConnection -DataReader $reader -Table posts -TruncateTable
```

`Write-*Table` also accepts an array of `[PSCustomObject]` through `-Data`, which is what the file-based
demos use. `Import-*Table` and `Export-*Table` are the file ↔ table shortcuts on top of that, and
`Invoke-*Query` / `Read-*Query` are the read paths — `Invoke-` returns everything at once,
`Read-` streams row by row.

Every function takes `-EnableException`. Callers normally switch it on once for a whole provider:

```powershell
$PSDefaultParameterValues = @{ "*-Sql*:EnableException" = $true }
```

## The function grid

Prefixes: **Sql** = SQL Server · **Ora** = Oracle · **Pg** = PostgreSQL · **Mdb** = MongoDB ·
**Mio** = MinIO.

### Connecting

| Function | Returns |
| --- | --- |
| `Connect-SqlInstance` | `SqlConnection`. `-Credential` is optional, so integrated security works. |
| `Connect-OraInstance` | `OracleConnection`. Has `-AsSysdba`. |
| `Connect-PgInstance` | `NpgsqlConnection`. |
| `Connect-MdbInstance` | `PSCustomObject` holding the Mdbc connection details. |
| `Connect-MioInstance` | `PSCustomObject` with script methods (`GetAuthorization`, `GetFileListParams`, …) that build the signed S3 requests the other `*Mio*` functions send. |

`Connect-SqlInstance`, `Connect-OraInstance` and `Connect-PgInstance` all take `-PooledConnection`.

### Reading

| Function | Purpose |
| --- | --- |
| `Invoke-SqlQuery` / `Invoke-OraQuery` / `Invoke-PgQuery` | Run a query, return the whole result. `-As` selects `PSObject` (default), `DataSet`, `DataTable`, `DataRow` or `SingleValue`. Supports `-ParameterValues` / `-ParameterTypes` and `-Transaction`. |
| `Read-SqlQuery` / `Read-OraQuery` / `Read-PgQuery` | Same query, streamed one object at a time instead of collected. |
| `Read-MdbCollection` | Query a collection with `-Filter`, `-Project`, `-Sort`, `-First`, `-Last`, `-Skip`. |
| `Get-SqlDataReader` / `Get-OraDataReader` / `Get-PgDataReader` | Return an open data reader over a `-Table` or a `-Query`, to be piped into a `Write-*Table`. |

### Writing

| Function | Purpose |
| --- | --- |
| `Write-SqlTable` / `Write-OraTable` / `Write-PgTable` | Bulk-load either `-Data` (objects) or `-DataReader` (streaming) into `-Table`. `-BatchSize` defaults to 1000, `-TruncateTable` empties first, `-Transaction` is supported. Reports progress with `Write-Progress -Id 1`. |

The three writers are siblings underneath as well as from the outside: each uses its own database's
bulk path — `SqlBulkCopy`, `OracleBulkCopy` and, since 2026-08-15, `COPY` through Npgsql's
`BeginTextImport`. `Write-PgTable` used to fill a `DataTable` and let an `NpgsqlDataAdapter` generate
the `INSERT` statements; that was entry 3 of `SIBLING-FINDINGS.md` and it is closed.

**`-BatchSize` means something different in `Write-PgTable`.** A `COPY` is one stream, so there is
nothing to split into batches and the parameter only says how often progress is reported. The two
other writers still hand it to their bulk copy as a real batch size.

Three more things about the PostgreSQL one, because its copy format is text and every value is
escaped by hand:

- **A `DateTime` is formatted with `ToString('o')`.** PowerShell renders numbers culture invariantly,
  but `"$someDate"` drops the milliseconds — and on this data only a minority of rows would show it.
- **A `byte[]` is written as `\\x…`, with the backslash doubled.** `\x` is an escape of the copy
  format itself, so a single one makes PostgreSQL decode the hex into raw bytes instead of handing
  the text to the `bytea` parser.
- **A `-DataReader` whose source has a column the target has not is refused**, the same way
  `Write-SqlTable` and `Write-OraTable` refuse it. The other direction is allowed: a target column the
  source does not have is not named in the `COPY` at all, so it keeps its default.
| `Write-MdbCollection` | Insert objects into a collection. `-Convert` reshapes each object, `-Id` and `-Property` control upserts. |
| `Remove-MdbCollection` | Drop a collection. |

### Files and tables

| Function | Purpose |
| --- | --- |
| `Import-SqlTable` / `Import-OraTable` / `Import-PgTable` | Read a file at `-Path` into `-Table`, with `-ColumnMap`, `-Encoding`, `-BatchSize` and `-TruncateTable`. |
| `Export-SqlTable` / `Export-OraTable` / `Export-PgTable` | Write `-Table` out to `-Path`. |
| `Get-SqlTableInformation` / `Get-OraTableInformation` / `Get-PgTableInformation` | Column metadata for one or more tables, used to build column mappings. |

### Object storage and drivers

| Function | Purpose |
| --- | --- |
| `Get-MioFileList` | List the objects in the connected bucket. |
| `Get-MioFile` | Download an object. |
| `Set-MioFile` | Upload an object. |
| `Remove-MioFile` | Delete an object. |
| `Import-OraLibrary` / `Import-PgLibrary` | Download `Oracle.ManagedDataAccess.dll` / `Npgsql.dll` from nuget.org into `lib/` and load them. |

## Gaps in the grid

The names are fixed by the naming grid, so the empty cells are worth writing down before anyone invents
a different name for them. **✔** marks what exists and **—** is a cell that makes no sense for that
provider:

| Family | SQL Server | Oracle | PostgreSQL | MongoDB | MinIO |
| --- | --- | --- | --- | --- | --- |
| Connect | ✔ `Connect-SqlInstance` | ✔ `Connect-OraInstance` | ✔ `Connect-PgInstance` | ✔ `Connect-MdbInstance` | ✔ `Connect-MioInstance` |
| Query, all at once | ✔ `Invoke-SqlQuery` | ✔ `Invoke-OraQuery` | ✔ `Invoke-PgQuery` | — | — |
| Query, streamed | ✔ `Read-SqlQuery` | ✔ `Read-OraQuery` | ✔ `Read-PgQuery` | ✔ `Read-MdbCollection` | — |
| Reader for streaming into a writer | ✔ `Get-SqlDataReader` | ✔ `Get-OraDataReader` | ✔ `Get-PgDataReader` | — | — |
| Bulk write | ✔ `Write-SqlTable` | ✔ `Write-OraTable` | ✔ `Write-PgTable` | ✔ `Write-MdbCollection` | — |
| File → table | ✔ `Import-SqlTable` | ✔ `Import-OraTable` | ✔ `Import-PgTable` | — | — |
| Table → file | ✔ `Export-SqlTable` | ✔ `Export-OraTable` | ✔ `Export-PgTable` | — | — |
| Column metadata | ✔ `Get-SqlTableInformation` | ✔ `Get-OraTableInformation` | ✔ `Get-PgTableInformation` | — | — |
| Drop | — | — | — | ✔ `Remove-MdbCollection` | ✔ `Remove-MioFile` |
| Whole files | — | — | — | — | ✔ `Get-MioFile`, `Get-MioFileList`, `Set-MioFile` |
| Load the driver | — | ✔ `Import-OraLibrary` | ✔ `Import-PgLibrary` | — | — |

Why the dashes are dashes:

- No `Import-Mdb*` / `Export-MdbCollection` and no `Get-MdbTableInformation` — the MongoDB demo writes
  objects that come from a relational source, and a schemaless collection has no column metadata to
  return.
- No `Get-MdbDataReader` — `Read-MdbCollection` already streams.
- No `Write-MioTable` or `Import-Mio*` — MinIO stores whole files, so `Set-MioFile` and `Get-MioFile`
  cover it.
- `Connect-SqlInstance` is the only `Connect-*` where `-Credential` is optional, and
  `Connect-OraInstance` is the only one without `-Database` (Oracle uses the service name in
  `-Instance`).
- Only Oracle and PostgreSQL need an `Import-*Library`: `System.Data.SqlClient` ships with .NET, and the
  MongoDB and MinIO paths need no DLL of their own.

**The `Mio` column is on its way out**, and its cells should not be filled in. MinIO changed its licence,
and uploading files is a different question from the one every other column answers — entry 9 of
`SIBLING-FINDINGS.md`. The column the sibling repository has and this one does not is **Kafka**, which is
entry 10 of the same file.

When you add a function to one provider, check whether the same function belongs in its siblings, and
either add it there too or record the reason here.
