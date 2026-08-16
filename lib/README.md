# lib/ — the data access layer

These 40 functions are the plumbing the demos build on. They are plain functions in plain files, loaded
by dot-sourcing rather than by a module, so that a demo can show exactly which code is being called:

```powershell
Import-Module -Name PSFramework
foreach ($file in (Get-ChildItem -Path ../lib/*-*.ps1)) { . $file.FullName }
```

`Import-Module PSFramework` has to come first — every function logs through `Write-PSFMessage` and
reports errors through `Stop-PSFFunction`. The Oracle and PostgreSQL functions additionally need
`Import-OraLibrary` / `Import-PgLibrary` / `Import-KfkLibrary`, which download the drivers from nuget.org into this
directory. `03_pwsh_setup.ps1` calls all three during setup, on Windows and inside WSL2, so a fresh clone has them before any container starts. Those `*.dll` and `*.so` files are gitignored.

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
**Kfk** = Kafka · **Mio** = MinIO, which is no longer part of the lab - see below.

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

### Event streaming

| Function | Purpose |
| --- | --- |
| `Connect-KfkProducer` | A producer for `-Instance`. Checks the connection before returning, so a broker that is not running fails here. |
| `Connect-KfkConsumer` | A consumer for `-Instance` in `-GroupId`. `-FromBeginning` sets `auto.offset.reset`. |
| `Write-KfkTopic` | Produce `-Data` to `-Topic` as JSON, one message per object, with an optional `-Key`. Flushes before returning. |
| `Read-KfkTopic` | Consume from `-Topic` and return `[PSCustomObject]`s, stopping after `-First` messages or `-Timeout` seconds of quiet. |
| `Remove-KfkTopic` | Delete `-Topic` on `-Instance` and wait until the broker has really dropped it. |

**There are two connect functions and that is deliberate.** Every other provider here has one
connection that reads and writes; Kafka has a producer and a consumer, which are different clients
with different configuration and nothing shared behind them. Inventing a `Connect-KfkInstance` would
mean inventing a connection Kafka does not have.

**A topic has no end, so `Read-KfkTopic` must be given a stopping rule.** Against a live topic only
`-First` is guaranteed to return: `-Timeout` waits for a gap in the messages, and while the shop is
producing there is never one. To read "everything" ask the broker for the high watermark first —
`demo/06_eventstreaming.ps1` shows it — because "everything" on a topic somebody is still writing to
is otherwise "forever".

**`-GroupId` is what Kafka remembers a reader by, and `-FromBeginning` is not a rewind.** It sets
`auto.offset.reset`, which only applies to a group that has never committed an offset. Passing it to
a group that has read before changes nothing at all, and there is no "start again" setting — starting
again means a new group id. In a demo that gets re-run this shows up as "the cell returned nothing
the second time" rather than as an error.

**`Remove-KfkTopic` takes `-Instance`, not `-Connection`, and that follows from the two connect
functions.** Deleting a topic is neither producing nor consuming, so neither client is the right
thing to hand over; it builds its own admin client, which is where the .NET client keeps operations
of this kind. `docker/photoservice-app.ps1` calls it next to `Remove-MdbCollection` when it clears
the previous run — the application restarts its ids at 1, so a topic that outlived the tables would
hold several customers with id 1 and `demo/06_eventstreaming.ps1` would replay all of them into one
primary key. It waits for the topic to disappear rather than returning on the broker's
acknowledgement, because the caller's next message would otherwise simply recreate it.

### Object storage and drivers

| Function | Purpose |
| --- | --- |
| `Get-MioFileList` | List the objects in the connected bucket. |
| `Get-MioFile` | Download an object. |
| `Set-MioFile` | Upload an object. |
| `Remove-MioFile` | Delete an object. |
| `Import-OraLibrary` / `Import-PgLibrary` / `Import-KfkLibrary` | Download the driver from nuget.org into `lib/` and load it. |

`Import-KfkLibrary` is the odd one of the three, because Kafka is the first driver here that is not
pure .NET. It fetches **two** packages — `Confluent.Kafka` for the managed wrapper and
`librdkafka.redist` for the native library underneath — and the native one has to end up in the same
directory as the managed assembly or the runtime will not find it. Three details are worth knowing
before touching it:

- **`lib/` is shared by three platforms.** Windows runs the demos, WSL2 runs `06_test_connections.ps1`,
  and the photoservice container mounts this directory read only. The native file has a different
  name on each (`librdkafka.dll`, `librdkafka.so`), so both live here at once and each platform
  fetches its own on first use — which is why the two downloads are guarded separately.
- **On Linux it takes the `centos8` build, not the plain one.** The plain build links
  `libsasl2.so.3` and Ubuntu ships `libsasl2.so.2`, so it cannot be loaded at all; the centos8 build
  has everything linked in and needs nothing but glibc. That is why no apt package has to be
  installed in WSL2 or in the container.
- **Nothing loads the native library explicitly.** `Confluent.Kafka.Library::Load` reaches it through
  `libdl`, which Ubuntu 24.04 no longer ships as a separate library, so asking for it by full path
  fails where doing nothing works.

## MinIO is on its way out of the lab

**The five `*-Mio*.ps1` files stay. The container does not.** MinIO changed its licence, and it answers a
different question from every other provider here — the rest of this library is about how rows get into
and out of a database and what happens to their types on the way, while MinIO is about uploading and
downloading a file. So it is leaving `docker/docker-compose.yaml`, the setup scripts and the demos,
and the code is being kept here instead of deleted. Entry 9 of `SIBLING-FINDINGS.md`.

**It has not left yet.** The `minio` service is still in the lab, because
`docker/photoservice-app.ps1` writes its logging archive to the bucket and the *"Transfer data from
logging (or kafka)"* section of `demo/04_photoservice.ps1` reads it back. That section is being ported
onto Kafka first — entry 10 — and MinIO goes out in the same change. Removing it before then would
empty half of demo 4 without failing, which is the one order that breaks something.

**Why the code is worth keeping.** `Connect-MioInstance` signs its own requests, and the whole scheme
is four lines you can read on a slide:

```powershell
$bytesToHash = [Text.Encoding]::ASCII.GetBytes("$Method`n`n$ContentType`n$Date`n/$bucket/$Key")
$bytesHashed = [System.Security.Cryptography.HMACSHA1]::new($bytesSecret).ComputeHash($bytesToHash)
"AWS " + $accessKey + ":" + [Convert]::ToBase64String($bytesHashed)
```

That is **AWS Signature Version 2** — verb, an empty Content-MD5, content type, date and
`/bucket/key`, joined by newlines, HMAC-SHA1 with the secret key, base64, into an
`Authorization: AWS <key>:<signature>` header. Not SigV4, which builds a canonical request and derives
a signing key through four chained HMAC-SHA256 rounds; this repository said SigV4 for a while and was
wrong. SigV2 is the older scheme and is why it fits on a slide at all.

It returns a `PSCustomObject` rather than a connection — HTTP has nothing to hold open — and that
object carries five script methods (`GetAuthorization`, `GetFileListParams`, `GetFileParams`,
`SetFileParams`, `RemoveFileParams`) which each build the signed `Invoke-WebRequest` splat for one
operation. The four verbs are thin wrappers around those.

**What using it looks like**, once there is a bucket to point at. Assembled from the call sites that
are being removed — `demo/init_stackexchange.ps1`, the *"Bonus: Getting data from MinIO"* section of
`demo/02_stackexchange.ps1`, the upload loop of `05_sample_data_setup.ps1` and the cleanup loop of
`docker/photoservice-app.ps1`:

```powershell
# Connect. Nothing is opened - this builds the object that signs the requests.
$credential = [PSCredential]::new('stackexchange', ('Passw0rd!' | ConvertTo-SecureString -AsPlainText -Force))
$mio = Connect-MioInstance -Instance '127.0.0.1' -Credential $credential -Bucket stackexchange

# Upload, either from a file or from a string in memory
Set-MioFile -Connection $mio -Key Users.xml -InFile ../data/stackexchange/Users.xml
Set-MioFile -Connection $mio -Key note.txt -Content 'written from memory'

# List. One object per key, with LastModified, ETag and Size.
Get-MioFileList -Connection $mio

# Download. Without -OutFile the content comes back as lines, so this is a line count.
$usersData = Get-MioFile -Connection $mio -Key Users.xml
$usersData.Count

# With -OutFile it is written to disk and nothing is returned
Get-MioFile -Connection $mio -Key Users.xml -OutFile ./Users.xml

# Delete
Remove-MioFile -Connection $mio -Key note.txt
```

`-ContentType` defaults to `text/plain; charset=UTF-8` on both `Get-MioFile` and `Set-MioFile`, and is
part of the signature, so it has to match what the object was stored with.

**To run any of it again** you need something S3-compatible on `-Instance` and a bucket the credential
may write to — a MinIO container of your own, or any other S3-compatible server. Two limits are worth
knowing before you try:

- **`-Instance` gets `:9000` appended** unless you pass a port yourself, because that is MinIO's
  default. `-Instance 'storage.example.com:443'` keeps its own port.
- **The URL is built as `http://`,** so this talks to plain HTTP only. Real AWS S3 is therefore out of
  reach without changing that line — and AWS has deprecated SigV2 for new regions anyway. Against a
  local container over HTTP, which is what it was written for, it works as it stands.

What leaves this repository is the container, its init script, the two bucket policies and the `.env`
block — not the ability to talk to a bucket.

## Gaps in the grid

The names are fixed by the naming grid, so the empty cells are worth writing down before anyone invents
a different name for them. **✔** marks what exists and **—** is a cell that makes no sense for that
provider:

| Family | SQL Server | Oracle | PostgreSQL | MongoDB | Kafka | MinIO |
| --- | --- | --- | --- | --- | --- | --- |
| Connect | ✔ `Connect-SqlInstance` | ✔ `Connect-OraInstance` | ✔ `Connect-PgInstance` | ✔ `Connect-MdbInstance` | ✔ `Connect-KfkProducer`, `Connect-KfkConsumer` | ✔ `Connect-MioInstance` |
| Query, all at once | ✔ `Invoke-SqlQuery` | ✔ `Invoke-OraQuery` | ✔ `Invoke-PgQuery` | — | — | — |
| Query, streamed | ✔ `Read-SqlQuery` | ✔ `Read-OraQuery` | ✔ `Read-PgQuery` | ✔ `Read-MdbCollection` | ✔ `Read-KfkTopic` | — |
| Reader for streaming into a writer | ✔ `Get-SqlDataReader` | ✔ `Get-OraDataReader` | ✔ `Get-PgDataReader` | — | — | — |
| Bulk write | ✔ `Write-SqlTable` | ✔ `Write-OraTable` | ✔ `Write-PgTable` | ✔ `Write-MdbCollection` | ✔ `Write-KfkTopic` | — |
| File → table | ✔ `Import-SqlTable` | ✔ `Import-OraTable` | ✔ `Import-PgTable` | — | — | — |
| Table → file | ✔ `Export-SqlTable` | ✔ `Export-OraTable` | ✔ `Export-PgTable` | — | — | — |
| Column metadata | ✔ `Get-SqlTableInformation` | ✔ `Get-OraTableInformation` | ✔ `Get-PgTableInformation` | — | — | — |
| Drop | — | — | — | ✔ `Remove-MdbCollection` | ✔ `Remove-KfkTopic` | ✔ `Remove-MioFile` |
| Whole files | — | — | — | — | — | ✔ `Get-MioFile`, `Get-MioFileList`, `Set-MioFile` |
| Load the driver | — | ✔ `Import-OraLibrary` | ✔ `Import-PgLibrary` | — | ✔ `Import-KfkLibrary` | — |

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
