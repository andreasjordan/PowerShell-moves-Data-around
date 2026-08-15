# SIBLING-FINDINGS.md

The work list that came out of porting this repository to
[Python moves Data around](https://github.com/andreasjordan/Python-moves-Data-around).

The findings were made **over there** and written down over there, in that repository's own
`SIBLING-FINDINGS.md`, because a session opened in this repository would never see them otherwise. This
file is that list, on this side, with what has since been done to it. It is also where an entry goes
when something is found here that has to be fixed *there* — the direction it points depends on the
entry, and each one says which.

For the design decisions of the port itself, and the measurements quoted below, see `DIFFERENCES.md` in
the Python repository.

---

# Done

## 1. Two PostgreSQL tables had no owner — **fixed**

`docker/postgres-stackexchange.sql` created 18 tables and handed out 16 owners. `Posts` and
`Import_Posts` stayed owned by `postgres`, so the `stackexchange` user could not read or write them at
all. Latent, because `demo/02_stackexchange.ps1` only imports `Users` and `Badges`.

The two missing `ALTER TABLE … OWNER TO stackexchange;` lines are in.

**Careful:** the init scripts of the postgres image only run on an empty data directory, so this does
nothing until the `postgres` volume is removed and the container recreated —
`docker compose down -v`. To check afterwards:

```
docker compose exec postgres psql -U stackexchange -d stackexchange -c "SELECT COUNT(*) FROM Posts"
```

## 2. A placeholder error message in `Write-PgTable` — **fixed**

The `-DataReader` branch reported `"???? failed: <message>"`, which was the message for the failure mode
that is hardest to debug. It now names the step like every other `Stop-PSFFunction` in the file, and it
passes `-Target $Table`, which it was also missing.

## 3. `Write-PgTable` did not use `COPY` — **fixed**

It filled a `DataTable` and let an `NpgsqlDataAdapter` with an `NpgsqlCommandBuilder` generate the
`INSERT` statements. It now writes to Npgsql's `BeginTextImport`, which is the counterpart of the
`SqlBulkCopy` and `OracleBulkCopy` its two siblings already used, so the three writers are siblings
underneath as well as from the outside. The `DataTable`, the adapter and the command builder are gone.

**Measured on 2026-08-15**, driving the shipped function against the live containers, same data and
same tables before and after:

| Case | `NpgsqlDataAdapter` | `COPY` |
| --- | --- | --- |
| `-Data`, 4512 `Comments.xml` rows | 18051 ms | **2642 ms** |
| `-DataReader`, the same 4512 rows PostgreSQL → PostgreSQL | 14885 ms | **3589 ms** |
| `-DataReader`, 12220 `Users` rows Oracle → PostgreSQL (demo 02 line 115) | 28388 ms | **23605 ms** |

The last row is the honest one: only about five seconds of it is the write, and reading 12220 rows
out of Oracle is the rest. Where the source is not the bottleneck the load is four to seven times
faster.

**Escaping, which is what the entry warned about.** Of the 4512 rows of `Comments.xml`, **24** carry a
newline or a backslash in `Text` — 15 and 9, and none carries a tab, which the entry had allowed for.
All 24 round-trip byte-exact, on both the `-Data` and the `-DataReader` path. Checked separately from
the bulk comparison so they could not hide in 4512 rows.

**Two things the escaping got wrong on the way, both found by running it:**

- **`\x` is an escape of the copy format itself.** A `byte[]` written as `\x0001…` is decoded by COPY
  into raw bytes rather than handed to the `bytea` parser as text, and the `0x00` then fails with
  `invalid byte sequence for encoding "UTF8"`. The backslash has to be doubled.
- **`"$value"` drops the milliseconds of a `DateTime`.** PowerShell converts numbers culture
  invariantly — verified on this `de-DE` machine — but `"$(Get-Date)"` renders `03/01/2024 12:34:56`.
  `DateTime` is therefore formatted with `ToString('o')`. This is the same defect the sibling's
  `import_ora_table` had, met from the other side.

**Three defects of the old implementation went with it**, none of them known before:

- A string like `'9876.5432'` bound for a `NUMERIC` column arrived as **98765432**. The `DataTable`
  parsed it in the current culture, where `.` is a thousands separator. Silent, and the worst of the
  three. `COPY` hands the text to PostgreSQL, which has no culture.
- `-Data` threw on a `PSObject`-wrapped integer — `Couldn't store <1> in id Column` — which is what
  `1..3 | ForEach-Object { [PSCustomObject]@{ id = $_ } }` produces.
- It could not write to a table created with `CREATE TABLE … (LIKE …)` at all: *"Dynamic SQL generation
  is not supported against a SelectCommand that does not return any base table information."*

**One deliberate change of behaviour, agreed with the owner:** a `-DataReader` whose source has a
column the target has not is now refused with *"No target column for source column X found."*, which
is what `Write-SqlTable` and `Write-OraTable` already did and what the Python `write_pg_table` does.

**Verified, and the verification was verified.** 42 checks pass and none is a row count: values are
compared column by column against `Comments.xml` and against the Oracle source, with the preconditions
asserted first — that 24 rows really do carry the special characters, that 12179 of 12220
`LastAccessDate` values really do carry milliseconds, that `AboutMe` is populated and contains
newlines. Transactions were checked in both directions (a rollback leaves both tables empty, a commit
lands both), because `photoservice-app.ps1` writes an order header and its details in one. Then the
backslash escape was **deliberately removed and the suite re-run**: it fails with
`22P04: missing data for column "userid"`, so the check can fail.

## 4. `04_docker_compose.sh` did not wait for the databases — **fixed**

It ran `docker compose up -d` and returned. Nothing checked that SQL Server had created the demo
databases. There was no failure, because `05_sample_data_setup.ps1` spent minutes downloading sample
data and that always gave the containers enough time — an accidental wait, and finding 5 was about to
remove it. The Python `05` finishes in about two seconds, and its `06` duly failed with
`08001 … error was encountered during handshakes before login` four seconds after `docker compose up`.

`04` now waits for SQL Server, PostgreSQL, MongoDB and Oracle, each by asking for the demo database its
init script creates **last**, and it waits for the docker daemon first. See finding 13.

## 5. The sample data was downloaded again on every run — **fixed**

Every run re-downloaded the archive from archive.org and the GPX and GeoJSON files. `05` now skips a
download when its files are already there, and `-Force` fetches them again. Three things came across
from the Python side with it:

- The three Geodata artifacts are checked one at a time, because they come from three different sites.
- Downloads go to `<name>.part` and are renamed only once the size matches `Content-Length`. This closes
  a second, quieter bug: a download cut off halfway used to leave a file that looks perfectly good and
  fails much later, inside demo 03, as a parse error that says nothing about a download.
- The StackExchange check is coarse — "are there any `*.xml`". It does not notice a half-extracted
  archive and should not try to; `-Force` is the answer to that.

## 6. The import loop depends on case-insensitive property access — **commented**

Not a defect. `Import-SqlTable`, `Import-OraTable` and `Import-PgTable` read `$rowObject.$sourceColumnName`,
where `$sourceColumnName` comes from the *target* table. Against PostgreSQL those names arrive lower
cased, because the tables are created unquoted and PostgreSQL folds them — while the XML attributes are
`Id`, `AboutMe`, `CreationDate`. It works only because PowerShell finds a property regardless of case.

It is recorded because it is invisible, and because it is exactly what broke the Python port: of the
fourteen columns of the PostgreSQL `Users` table, **zero** match an attribute of `Users.xml` by exact
name. A case-sensitive lookup fills every column with `NULL`, reports the right number of rows and
returns success. All three functions now carry a comment saying so.

## 7. `03_geodata.ps1` said 27 features, the file has 258 — **fixed**

The demo commented `$geoJSON.features.Count  # 27 - only the EU`, but the line in `05` that would have
reduced the download to the EU was commented out. Measured against the same URL: 14.6 MB, **258
features**, largest geometry 1.5 MB of JSON (Canada).

Decided in favour of the full set, matching the Python port: the comment now states the real count, and
`05` says why the filter stays off. The large geometries are what make the 4000-character `CLOB` guard
in `Invoke-OraQuery` matter.

## 8. `photoservice-app.ps1` wrote an order event with no order — **fixed**

The `NewPayment` and `NewShipment` blocks picked their order with a query that may legitimately return
nothing — the payment loop runs once a second and can catch up with the order loop. `$payment.OrderId`
was then `$null`, the `UPDATE` matched no row, and the `INSERT INTO order_event` wrote a row whose
`order_id` is `NULL`. Both blocks are now guarded, with the reschedule left outside the guard so the
loop does not spin. To check:

```sql
SELECT COUNT(*) FROM order_event WHERE order_id IS NULL;
```

## 11. The password was not configured in `docker/.env` — **fixed**

`Passw0rd!` appears 22 times across 15 files in `docker/`. `.env` fed four container environment
variables; everything else had it as a literal, including `sqlserver-init.sh` six times **inside a
container that already has `MSSQL_SA_PASSWORD` in its environment**. So changing `docker/.env` broke the
setup in places that look unrelated to it, while `README.md` said the password "is configured in
`docker/.env`".

`sqlserver-init.sh` now uses `$MSSQL_SA_PASSWORD` and `04_docker_compose.sh` sources `docker/.env` for
its probes. The `CREATE USER` statements are unchanged **on purpose** — making those interpolate needs an
entrypoint that rewrites SQL, and the visible literal is part of the teaching. `README.md` now says
which files still hold it.

## 12. `06_test_connections.ps1` checked the wrong machine — **fixed**

Every setup step ran inside WSL2, including the connection test, while the demos are run from Windows.
The setup could finish completely green while the machine that runs the demo could not reach a single
database.

`01_setup.ps1` now installs the modules on Windows first and runs `06_test_connections.ps1` a second
time there at the end. Two things came with it:

- **One list of modules.** Doing this produced a second list, one per side, which is exactly the drift
  the Python repository had already suffered twice. `modules.txt` is now the only place they are named,
  and `03_pwsh_setup.ps1` takes a `-Scope` so the same script serves both sides.
- **Wait for the port forwarding before checking from Windows.** See below.

It also gained the block for ProjectStatus, which had never been added.

## 13. The docker daemon was not waited for either — **fixed**

One layer below finding 4. `02_wsl2_setup.sh` starts docker, but `01_setup.ps1` runs `wsl --shutdown`
straight afterwards and `start_demo.ps1` runs after a reboot, so in both cases the daemon comes back
only because systemd starts it — a race against a `docker compose up` seconds after WSL2 boots.

The more useful half was what happened when a wait failed: nothing. The probes have to discard stderr,
because for most of the wait "that user does not exist yet" *is* the correct answer, so the give-up path
printed one line with no cause — and it kept probing for the full timeout even when the container had
already exited, so a container killed by its `mem_limit` looked exactly like a slow one.

`04` now polls `docker info` first, checks `docker compose ps --status running` on each round and stops
early if the container is gone, and prints `docker compose logs --tail 50` on the failure path. The
first argument of `wait_for` is the compose service name, so the message names what you would type next.

## 14. Both repositories could not share one WSL2 installation — **fixed**

They were always meant to: neither passes `-d` to `wsl`, so both use the default distribution. But
neither setup could be run while the other repository's containers existed, and `01_setup.ps1` ended by
entering a shell that kept its own containers alive, so there was no state in which both were merely
installed.

And it was worse than a port conflict. Both stacks publish the same ports, use the same password and
create the same database names, so `06_test_connections.ps1` would connect to the *other* repository's
volumes and report green — while `04` had no `set -e` and ended on `cd ..`, so a failed
`docker compose up` exited 0.

All four parts are done: `set -e` in `02` and `04`; `04` stops the `python-moves-data-around` project by
label before `docker compose up`; `01_setup.ps1` ends with `docker compose stop`; and
`start_containers.ps1` is now `start_demo.ps1`, matching the sibling's name.

**Still unproven: the switch itself.** Neither side has ever had anything to stop until now. Switch back
and forth once in each direction and check that each `04` reports stopping the other project.

### Also from 12: the port forwarding arrives late

`127.0.0.1:1521` is docker's published port inside WSL2 and a `wslrelay` listener on Windows, and the
relay does not publish every port at the same moment. On the Python repository's first clean install,
four forwards were up and 1521 was not — which failed the check while Oracle was running and answering
inside WSL2. `WinError 10061` is a refusal at connect time: nothing was listening on the Windows side.
The error names Oracle and means the network.

`01_setup.ps1` waits for all five database ports to accept a connection from Windows before it runs `06`
there, and `07_check_ports.ps1` is the diagnostic for when that is not enough. **Why one port lags the
others is not established** — do not write down a mechanism for it without evidence.

---

## 9. Remove MinIO — **done**

MinIO is out of the lab as of 2026-08-15, together with entry 10 and in the same change, which is the
order this section argued for: the application could not stop writing to the bucket until it had
somewhere else to write.

Deleted: the `minio` service, `minio-init.sh`, both policy files and the `.env` block; the upload loop
in `05_sample_data_setup.ps1` and the connection above it, which was the only thing there that needed
`lib/` at all; the connections in both `init_*.ps1` and in `06_test_connections.ps1`; the two ports in
`07_check_ports.ps1` and the one in the port wait of `01_setup.ps1`; the bucket section at the end of
`demo/02_stackexchange.ps1`; and both MinIO sections of `demo/04_photoservice.ps1`.

**The five `lib/*-Mio*.ps1` functions are kept, and that is the decision this entry was missing.** It
asked where to put the hand-rolled signing before `git rm` took it. The answer is `lib/README.md`,
which now has a *"MinIO is on its way out of the lab"* section with a worked example of all five
functions, assembled from the call sites listed above before they were deleted. Worth knowing: no demo
ever called `Set-MioFile`, so a reader following the demos never saw half the surface.

**It was never SigV4.** `Connect-MioInstance` signs with **AWS Signature Version 2** — HMAC-SHA1 over
`verb \n content-md5 \n content-type \n date \n /bucket/key`, base64, into an
`Authorization: AWS <key>:<signature>` header. This file, `AGENTS.md` and the sibling's
`DIFFERENCES.md` all called it SigV4. The code was always correct; only the description was wrong.

**Two limits are documented now that no demo had to care about:** `-Instance` gets `:9000` appended
unless a port is given, and the URL is built as `http://`, so it reaches a local container and not
real S3.

**In the Python port:** done long ago, and completely — no functions were kept there.

## 10. Port the event streaming demo back — **done**

`demo/06_eventstreaming.ps1` exists, and the `kfk` column of `lib/` with it, so the two repositories
can be shown side by side for event streaming again.

**What was built:** `Import-KfkLibrary`, `Connect-KfkProducer`, `Connect-KfkConsumer`, `Write-KfkTopic`
and `Read-KfkTopic`; the `redpanda` and `redpanda-console` services copied from the sibling,
advertising two listeners; the producer in `docker/photoservice-app.ps1`; and the demo.
`Confluent.Kafka` wraps the same librdkafka the Python `confluent-kafka` package does, so the two
demos are near-identical in shape rather than merely analogous, which was the point.

**The four traps transferred, and all four were met:**

1. **Two advertised listeners.** Copied from the sibling's compose file unchanged.
2. **Reading a live topic without a bound never returns.** `Read-KfkTopic` takes `-First` and
   `-Timeout`, and the demo asks the broker for the high watermark before replaying.
3. **`auto.offset.reset` only applies to a group with no committed offset.** Proven against the live
   broker: a new group with `-FromBeginning` read all 50 messages, the same group id read 0 the second
   time, and a different group id read all 50 again.
4. **The two-minute clock.** Said at the top of the demo and in `README.md`.

**Four things the .NET client forced that the Python one did not, none of them in the entry:**

- **`Import-KfkLibrary` fetches two packages, not one.** Kafka is the first driver here that is not
  pure .NET: `Confluent.Kafka` is the managed wrapper and `librdkafka.redist` carries the native
  library, which has to sit in the same directory as the managed assembly.
- **`lib/` is shared by Windows, WSL2 and the container.** The native file is named differently on
  each, so both live there at once and the two downloads are guarded separately.
- **On Linux the plain `librdkafka.so` cannot be loaded at all.** It links `libsasl2.so.3` and Ubuntu
  ships `libsasl2.so.2`. The `centos8` build in the same package has everything linked in, so it is
  used instead — which is why no apt package had to be added to WSL2 or the container.
- **There is no `producer.list_topics()`.** Metadata belongs to the admin client in .NET, so both
  connect functions build a dependent admin client to prove the broker answers.

**Also aligned with the sibling while there:** the application's `Appname` said `PictureService` and
now says `PhotoService`; only events carrying details reach the topic, so scheduling chatter stays on
the console; the per-iteration `Starting Loop` event is gone, which used to be produced every 100
milliseconds and which demo 4 had to skip by name; and `Added order to MongoDB collection` no longer
carries details, because the sibling does not put it on the topic either.

**Verified against live containers**, not by reading: 14 checks on the five functions, including a
value-by-value round trip of nested messages; then the demo itself run end to end, and the replayed
tables compared to PostgreSQL row by row — 156 customers, 766 order headers and 10522 order details,
**0 differences** on every column, with 742 payment and 717 shipment uuids actually compared so the
fold was doing work. The narration has not been stepped through by the owner yet.

---

# Open

**Nothing.** Entries 3, 9 and 10 were the last three and all closed on 2026-08-15. The one thing
outstanding is not work on this list: `demo/06_eventstreaming.ps1` is new narration the owner has
not stepped through yet.

New entries go here, or under "For the other side" when they point at the Python repository.

---

# For the other side

## 15. The PostgreSQL wait in `04_docker_compose.sh` returns too early — **fixed there, and now measured**

**Where:** `04_docker_compose.sh` in the **Python** repository, which has the version this one was
copied from

**What:** the probe is `SELECT COUNT(*) FROM pg_database WHERE datname = 'stackexchange'`. PostgreSQL
runs the files in `/docker-entrypoint-initdb.d` in alphabetical order, so `stackexchange.sql` is the
last of the three — but `CREATE DATABASE stackexchange` is the **first statement of that file**. The
wait therefore returns while the 18 tables behind it are still being created, which is the same class
of mistake finding 4 was about, one level down.

The SQL Server and Oracle probes in the same script do not have this: they ask for the database created
last and for a *table* respectively.

**Effect:** small, because creating 18 tables takes milliseconds. It is a hole rather than a failure —
but it is the hole the whole wait exists to close, and `docker/` is identical in both repositories, so
the reasoning transfers unchanged.

**Fix, applied here:**

```bash
wait_for postgres 150 \
    docker compose exec -T postgres psql -U postgres -d stackexchange -tAc \
    "SELECT COUNT(*) FROM pg_tables WHERE tablename = 'import_votetypes'"
```

`Import_VoteTypes` is the last `CREATE TABLE` in that file, and PostgreSQL folds the name to lower
case. While the database does not exist yet, `psql -d stackexchange` simply fails and the probe keeps
waiting, which is the behaviour it already had.

**Applied in the Python repository on 2026-08-15, and the hole was measured rather than argued.** The
postgres volume was deleted so the init scripts ran again, and the container log gives the timeline:

```
10:16:23.828  running /docker-entrypoint-initdb.d/stackexchange.sql
10:16:24.088  CREATE DATABASE            <- the old probe becomes true here
10:16:24.302  LOG:  shutting down        <- all 18 CREATE TABLEs happened in this gap
10:16:24.803  FATAL:  the database system is shutting down
10:16:26.331  FATAL:  the database system is shutting down
10:16:27.202  database system is ready to accept connections   <- the real server
```

**The window is 214 ms**, and every one of the 18 tables is created inside it.

**And the probe really can land there**, which was the part worth checking: the postgres entrypoint runs
the init files against a *temporary* server started with `listen_addresses=''`, so it is reachable only
over the unix socket inside the container — which is exactly the path `docker compose exec -T postgres
psql` takes. The two `FATAL: the database system is shutting down` lines above are the polling probes of
the test being refused, so the connection demonstrably gets through to that server.

With `sleep 2` between attempts, that is roughly a **one-in-ten chance per start** of the wait returning
about three seconds early against a schema that is still being built. The other nine times it passes by
luck, which is why nobody had seen it fail.

**One residual, deliberately not fixed.** Both the old and the new probe can be satisfied by that
temporary server, which then shuts down before the real one starts — so neither proves the final server
is up. The new probe at least guarantees the *schema is complete* when it returns, which is what the
wait is for, and in both repositories the mongo and Oracle waits follow and take far longer than the
three seconds postgres needs to come back. Worth knowing before anything is reordered.

## 16. Nothing holds WSL2 open while the Windows half of `01_setup.ps1` runs — **fixed there**

**Where:** `01_setup.ps1` in the **Python** repository — the stretch from the port-forwarding wait to
`docker compose stop`

**What:** WSL2 terminates the distribution a few seconds after its last process exits, and every
container goes with it. While the setup is one `wsl` call after another that never happens. The Windows
half — the port wait, then `python 06_test_connections.py` on Windows — is the first stretch during
which **no `wsl` process is alive**, and both repositories now have one.

**Effect, measured here on the first run that had it:** the last WSL2 step finished at 20:56:01, and at
20:56:16 every container logged a shutdown — postgres `received fast shutdown request`, mongo a
`SignalHandler` shutdown in the same second. The Windows connection test was two connections into its
run; the next one failed with `Failed to connect to 127.0.0.1:5432`, against a database that had been
gone for one second.

**Fix, applied here:** start a background `wsl sleep` before the port wait and stop it after
`docker compose stop`:

```powershell
$keepWsl2Alive = Start-Process -FilePath wsl -ArgumentList 'sleep', '900' -PassThru -NoNewWindow
...
Stop-Process -InputObject $keepWsl2Alive -ErrorAction Ignore
```

**Worth re-examining over there, and this is the reason to write it down rather than just fix it.** The
Python repository's *"the port forwarding arrives late"* entry describes a `DPY-6005` on Oracle from
Windows on its first clean install, seconds after the same script had reached the same database from
inside WSL2. That is the same shape as this failure, and the ports were confirmed healthy only
*afterwards*, with the containers up again. The port-forwarding effect is real and separately
evidenced — five ports, four relays present, one missing — so this does not simply replace it. But a
container that has been shut down and a forward that has not appeared yet are **indistinguishable from
the driver's error message**, and only one of the two was considered at the time. The container log
settles it, and the timestamps are UTC there while the script output is local.

**Applied in the Python repository on 2026-08-15**, in the same shape as here: the `Start-Process` goes
in immediately before the port-forwarding wait, and the `Stop-Process` immediately after
`docker compose stop`, so the whole Windows half is covered and nothing after the stop needs to be.

**Still not verified by a full `01_setup.ps1` run**, and it cannot be cheaply — proving it means letting
the setup run end to end on a machine where it would otherwise fail, which costs an Oracle start on both
sides. What *is* now confirmed is the mechanism it defends against, from the other direction: an agent
driving these containers has to hold WSL2 open with exactly this `wsl sleep` trick, because without it
the stack is gone between one tool call and the next. That is the same effect, met deliberately instead
of by accident.

## 17. The PhotoService schedule makes its own demo expensive to test — **fixed both sides**

**Where:** `docker/photoservice-app.ps1` here, lines 73-87, and `docker/photoservice-app.py` in the
**Python** repository, which keeps the same numbers. **This one points both ways** — it has to land on
both sides in the same turn, because the schedule is part of what the two demos are compared on.

**What:** the application staggers its work with four `NextRun` offsets taken from the moment it starts:

```powershell
$newOrder    = @{ DelaySec = 1; NextRun = (Get-Date).AddMinutes(10); NextId = 1 }
$newPayment  = @{ DelaySec = 1; NextRun = (Get-Date).AddMinutes(15) }
$newShipment = @{ DelaySec = 1; NextRun = (Get-Date).AddMinutes(20) }
```

Customers start immediately; orders are ten minutes out, payments fifteen, shipments twenty.

**Effect:** the second half of demo 4 has nothing to find for twenty minutes after every container
start — and in the sibling, demo 6 reads the events rather than the tables, so it is stricter still.
`docker compose restart photoservice` truncates the tables and restarts the clock, and so does every
switch between the two repositories, which is what makes switching cost twenty minutes rather than the
one minute the container start actually takes. A run inside that window looks broken and is not.

It is also why `AGENTS.md` on both sides has to tell people to put PhotoService last and switch once.
That advice exists only to work around this.

**Fixed on 2026-08-15, scaled down by ten**, in `photoservice-app.ps1` and `photoservice-app.py` in the
same turn:

| | was | is |
| --- | --- | --- |
| first order | 10 min | 60 s |
| first payment | 15 min | 90 s |
| first shipment | 20 min | 120 s |
| new customer every | 60 s | 6 s |
| new logging archive every (PowerShell only) | 120 s | 12 s |

**The customer interval was scaled with the offsets rather than left alone**, and that is the part
worth not getting wrong: what the demo shows is a *proportion*. At 60 seconds against a ten-minute
offset, ten customers existed by the time the first order was placed. At 6 seconds against 60, ten
still do. Scaling only the offsets would have started the orders against a single customer.

The one-second intervals for orders, payments and shipments are unchanged — they cannot scale down
meaningfully and were already the fast end of this.

**The advice that existed to work around it is gone in the same commit**, from both `AGENTS.md` files
and both `README.md` files: putting demos 4 and 6 last on each side and switching only once. Switching
now costs about as long as the containers take to come up.

**The one notebook that quoted the old numbers was corrected too.** `demo/06_eventstreaming.ipynb`
opened with *"Give the shop twenty minutes before running this"* and then listed the whole schedule.
That is a **markdown** cell, so fixing it needed no run and touched no outputs — 23 cells and 13
outputs before and after, three lines changed, done with the raw exact-match replacement. Had it been a
code cell it would have been left for the owner.

The committed outputs in that notebook were produced under the old schedule. Nothing in them quotes a
duration, so they are not now wrong, but they are the counts of a twenty-minute run and the next pass
through the notebook will produce smaller ones.

## 18. SQL Server uses `DATETIME`, so it cannot hold what Oracle and PostgreSQL hold — **fixed both sides**

**Where:** `docker/sqlserver-stackexchange.sql`, **22 columns**. The file is byte-identical in both
repositories, so **this points both ways** and has to land on both sides together.

**What:** every timestamp column in the StackExchange schema is `DATETIME`, whose granularity is about
3.33 ms — it stores only .000, .003 and .007 within a hundredth. The Oracle and PostgreSQL schemas use
`TIMESTAMP(3)`, which holds exact milliseconds. So the same source file lands differently in the three
databases, and only SQL Server is lossy.

It is 11 columns, each once in the real table and once in its `Import_` staging twin:

```
Badges/Comments/PostLinks/Votes  CreationDate
Users                            CreationDate, LastAccessDate
Posts                            ClosedDate, CommunityOwnedDate, CreationDate,
                                 LastActivityDate, LastEditDate
```

**Measured on 2026-08-15**, driving the shipped `import_*_table` functions against live containers and
comparing every value back to `Users.xml`:

| Provider | Column type | Result over 12220 rows |
| --- | --- | --- |
| PostgreSQL | `TIMESTAMP(3)` | 0 differ, exact |
| Oracle | `TIMESTAMP(3)` | 0 differ, exact |
| SQL Server | `DATETIME` | exact equality impossible; passes only within a 4 ms tolerance |

`Users.xml` is a good witness for this: **12179 of its 12220 rows carry real milliseconds**, while every
single `CreationDate` ends in `.000`. That asymmetry is why the original `import_ora_table` bug was so
hard to see, and it is the same asymmetry that hides this one.

**Why it matters more here than the 3 ms suggests.** The point of the scenario is the same data shown
through three providers side by side. A column that silently rounds in one of the three makes that
comparison unequal in a way no narration mentions — and "the row count is right, so the import worked"
is exactly the trap `AGENTS.md` warns about on both sides.

**Fixed on 2026-08-15:** `DATETIME` → `DATETIME2(3)` in all 22 places, in both repositories. The file
is still byte-identical on the two sides.

**And measured again afterwards, which is the point.** The same check that produced the table above,
re-run against the migrated schema with the tolerance removed:

| Provider | Column type | Result over 12220 rows |
| --- | --- | --- |
| SQL Server | `DATETIME2(3)` | **0 differ, exact** — no tolerance needed any more |
| PostgreSQL | `TIMESTAMP(3)` | 0 differ, exact |
| Oracle | `TIMESTAMP(3)` | 0 differ, exact |

The three providers now hold the same values, which is what the scenario claims to show.

Two practical notes, the first of which caught us:

- **Editing the init SQL changes nothing on an existing machine.** These files run only when the
  SQL Server volume is created, so **both** stacks had to be migrated by hand — this one first, then
  the sibling's after switching to it. The pass is an `ALTER TABLE ... ALTER COLUMN` generated from
  `sys.columns`, so that each column keeps its own nullability instead of it being guessed at, and it
  only touches columns that are still `datetime`, which makes it safe to run twice. Both volumes are
  done and both were re-measured afterwards at 9/9 with the tolerance removed. A machine that installs
  from scratch from here on gets `DATETIME2(3)` from the init SQL and needs none of this.
- `DATETIME2(3)` is not merely wider: it is 7 bytes rather than 8, and its range starts at year 0001
  instead of 1753. Neither matters for this data.

---

## 19. `created_at` was neither local nor consistent — **fixed both sides**

**Where:** `docker/photoservice-app.ps1` and `docker/docker-compose.yaml` here, and the same two files
in the **Python** repository. **This one points both ways** and had to land on both, because the two
applications have to agree on what the column means.

**Decided by the owner on 2026-08-15: local time.** UTC is the better default in general, and the
argument against it here is that a demo is read off a wall clock — an order placed at 18:23 that
pgAdmin shows as 16:23 costs a minute of explaining that has nothing to do with moving data. DST is
not a risk because nobody demos across a changeover. The logging event's own `Timestamp` field stays
UTC on both sides, so one message does carry both conventions; that is deliberate and is the one
place where the two disagree.

**There were two separate problems, and the first entry only found one of them.**

**1. Npgsql converted the value on the way in.** A `DateTime` whose `Kind` is `Local` becomes UTC in a
`TIMESTAMP` column. Measured over 766 order headers: the Kafka event said `18:23:56.418+02:00` and the
column held `16:23:56.418` — the same instant, two different readings, and a replay through demo 6
therefore landed a different value in SQL Server than the direct PostgreSQL transfer in demo 4.
`Get-LocalTimestamp` now hands over `[datetime]::SpecifyKind([datetime]::Now, 'Unspecified')`, which
is what the column actually is: a wall clock with no zone. Verified afterwards — the topic and the
column agree to the millisecond, and the JSON no longer carries an offset at all.

**2. The container had no time zone, so "local" was UTC.** This is the part the first write-up missed
and it is the one that actually decided what the demo shows. Neither application image has a usable
zone: the PowerShell image has no `tzdata` at all, so `TZ` alone does nothing, and the Python image
has `tzdata` but an `/etc/localtime` pointing at UTC. Both containers therefore ran on UTC while WSL2
and Windows were on CEST. Fixing only the first problem stored a consistent value that was still two
hours behind the wall clock. Both compose files now mount `- /etc/localtime:/etc/localtime:ro`, which
is enough for .NET and for Python and needs no package installed.

**A correction to the first version of this entry.** It claimed the two repositories held `created_at`
two hours apart, psycopg writing local where Npgsql wrote UTC. That was **inferred and wrong**: the
sibling's container was on UTC too, so both sides held UTC and there was no gap between them. The
measured 120-minute gap was *inside this repository*, between what the event said and what the column
held. Both are fixed now and both sides store the same wall clock.

**Not established, and deliberately not guessed at:** the container reported `+02:00` earlier in the
same session and UTC later, with no change to its configuration in between. The mount removes the
question rather than answering it. Do not write down a mechanism for it without evidence.


Add an entry above when something is found in this repository that belongs in the Python one, and say
plainly which direction it points — the file is read from both sides.
