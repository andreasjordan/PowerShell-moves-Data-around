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

The grid is intentionally not square. MongoDB and MinIO are demonstrated at a narrower scope than the
three relational databases, so these cells are simply not implemented:

- No `Import-Mdb*` / `Export-MdbCollection` and no `Get-MdbTableInformation` — the MongoDB demo writes
  objects that come from a relational source, and a schemaless collection has no column metadata to
  return.
- No `Get-MdbDataReader` — `Read-MdbCollection` already streams.
- No `Write-MioTable` or `Import-Mio*` — MinIO stores whole files, so `Set-MioFile` and `Get-MioFile`
  cover it.
- `Connect-SqlInstance` is the only `Connect-*` where `-Credential` is optional, and
  `Connect-OraInstance` is the only one without `-Database` (Oracle uses the service name in
  `-Instance`).

When you add a function to one provider, check whether the same function belongs in its siblings, and
either add it there too or record the reason here.
