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

# Open

## 3. `Write-PgTable` does not use `COPY`

**Where:** `lib/Write-PgTable.ps1`

It fills a `DataTable` and lets an `NpgsqlDataAdapter` with an `NpgsqlCommandBuilder` generate the
`INSERT` statements. PostgreSQL's own bulk path is not used. A long-standing wish rather than a defect.

**Evidence from the Python port**, `Users.xml`, 12220 rows into the same table on the same container:

| Approach | Result |
| --- | --- |
| `executemany`, converted values | 1.27 s |
| `executemany`, raw strings | 0.95 s |
| `COPY`, converted values | 0.30 s |
| `COPY`, raw strings | 0.14 s |

**Fix:** Npgsql exposes `BeginTextImport` and `BeginBinaryImport`. The text variant is the closer match
to what the Python port does — it writes the values as text and lets PostgreSQL parse them into the
column types, which removes the type handling entirely. The binary variant is faster again but needs the
correct .NET type per column.

**Worth checking while there:** escaping. In the Python port, 24 of the 4512 rows of `Comments.xml`
contain a tab, a newline or a backslash in `Text`, and all of them round-trip byte-exact. That is the
test case for any `COPY` implementation. **This one cannot be shipped on static checks** — see the
verification section of `AGENTS.md`.

**In the Python port:** both `write_pg_table` and `import_pg_table` use `COPY`, with raw strings for the
file import, so that side carries no type conversion for PostgreSQL at all.

## 9. Remove MinIO

**Where:** `lib/*-Mio*.ps1`, `docker/`, `05_sample_data_setup.ps1`, `demo/02_stackexchange.ps1`,
`demo/04_photoservice.ps1`, `demo/init_stackexchange.ps1`, `demo/init_photoservice.ps1`,
`06_test_connections.ps1`, `docker/photoservice-app.ps1`

MinIO comes out for two reasons, either of which would have been enough: it **changed its licence**, and
it is **not what this repository is about** — every other provider here answers the question "how do rows
get into and out of a database, and what happens to their types on the way", while MinIO answers "how
does a file get uploaded and downloaded".

**What that touches:**

- The five functions: `Connect-MioInstance`, `Get-MioFile`, `Get-MioFileList`, `Set-MioFile`,
  `Remove-MioFile`.
- The `minio` service in `docker/docker-compose.yaml`, plus `minio-init.sh`, the two policy files and
  the `.env` block.
- The upload block in `05_sample_data_setup.ps1` and the two ports in `07_check_ports.ps1`.
- The bucket section at the end of `demo/02_stackexchange.ps1`.
- In `demo/04_photoservice.ps1`: *"Transfer data from logging (or kafka)"* and the
  *"Bonus: Import Logging from files on MinIO"* section. The first of those does **not** simply
  disappear — see entry 10, which is where it goes.
- `photoservice-app.ps1` writes its logging archive to the bucket, and clears the bucket at startup.
  That has to become the Kafka producer of entry 10, or the application stops emitting events at all.

**Worth thinking about before deleting:** the hand-rolled AWS SigV4 signing in `Connect-MioInstance` is
the most interesting code in either repository, precisely because no SDK hides it. Deleting it removes
something genuinely good. Keeping it somewhere outside the demo — a gist, a blog post, an appendix — is
worth five minutes of thought before `git rm`.

**In the Python port:** done, completely. No demo uses it, the user-facing documentation does not mention
it, and the service, its init script, both policy files and the `.env` block have been deleted. Use that
side as the worked example of what to remove.

## 10. Port the event streaming demo back

**Where:** new — the counterpart of `demo/06_eventstreaming.ipynb` and the `kfk` functions over there

The Python repository now has a Kafka demo, served by Redpanda, and it is the only thing there with no
PowerShell counterpart. It exists because dropping MinIO also dropped the event streaming story, which
was collateral damage from a decision about *object storage* — and this repository's own section title,
*"Transfer data from logging (or kafka)"*, says what the real answer always was.

**The good news, and it decides the approach:** the .NET client `Confluent.Kafka` wraps **librdkafka**,
which is the same C library the Python `confluent-kafka` package wraps. The two demos would be
near-identical in shape rather than merely analogous — which is the whole point of the two repositories.
And the mechanism is already here: `Import-PgLibrary` and `Import-OraLibrary` download ADO.NET DLLs from
nuget.org at runtime, so **`Import-KfkLibrary` follows that pattern exactly**, with no new idea required.

**What to build:**

| There | Here |
| --- | --- |
| `connect_kfk_producer` | `Connect-KfkProducer` |
| `connect_kfk_consumer` | `Connect-KfkConsumer` |
| `write_kfk_topic` | `Write-KfkTopic` |
| `read_kfk_topic` | `Read-KfkTopic` |

Two connect functions rather than one, because Kafka has no single connection object — a producer and a
consumer are different clients. That is worth keeping on both sides.

Plus: the `redpanda` and `redpanda-console` services in `docker/docker-compose.yaml` (copy them from
there), the producer calls in `photoservice-app.ps1`, and a `demo/06_eventstreaming.ps1`.

**Four things learned the hard way over there, all of which transfer:**

1. **Advertise two listeners.** The application container reaches the broker as `redpanda:9092` on the
   compose network; the demo reaches it from Windows as `127.0.0.1:19092`. A broker advertises the
   address a client should come back on, so it has to advertise both. Getting this wrong is the classic
   Kafka-in-Docker trap.
2. **Reading a live topic without a bound never returns.** A stopping rule of "n seconds with no new
   message" never fires while the shop is producing. Ask the broker for the high watermark and read
   exactly that many. This hung a kernel over there, and interrupting a process inside librdkafka is
   unreliable — it had to be killed.
3. **`auto.offset.reset` only applies to a consumer group that has no committed offset.** There is no
   "start again" setting; starting again means a new group id. In a demo that gets re-run constantly this
   shows up as "the cell returned nothing the second time" rather than as an error.
4. **The application truncates its tables at startup and staggers its work over twenty minutes.** A demo
   run inside that window shows an empty topic and zero counts, and looks broken when it is not.

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

## 17. The PhotoService schedule makes its own demo expensive to test

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

**Fix, not yet applied and needing a decision on the numbers:** the *relative* order is what the demo
teaches — a customer, then an order, then a payment, then a shipment — and nothing about the story
needs those gaps to be ten minutes. Scaling them down by ten, to one minute, ninety seconds and two
minutes, keeps the sequence intact and makes the demo testable in the time a container takes to become
healthy. Whether to go further, to seconds, is a judgement about how it reads live: too fast and the
staggering stops being visible while narrating.

Whatever is chosen, **both applications change together and the two `AGENTS.md` notes about putting
PhotoService last come out in the same commit.**

---

Add an entry above when something is found in this repository that belongs in the Python one, and say
plainly which direction it points — the file is read from both sides.

One thing is worth carrying over when it is done here, because it changes the sibling too:

- **MinIO and Kafka**, entries 9 and 10 above. Until they are done, the two repositories cannot be shown
  side by side for those sections, because one side is empty.
