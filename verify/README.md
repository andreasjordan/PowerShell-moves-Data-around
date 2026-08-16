# verify/

The known-good numbers of `AGENTS.md`, made runnable.

**This is not a test suite.** There is no Pester, no framework, no CI, no fixtures and no mocking, and
`01_setup.ps1` does not call any of it. These are plain scripts that drive the shipped `lib/`
functions against the live containers and print `PASS` or `FAIL` per fact. They exist because the
alternative — every agent writing the same checks again in a scratchpad and throwing them away — has
a cost that took a while to become obvious.

## Why this folder exists

`AGENTS.md` says *"Reproduce these rather than inventing a new check"* and then gives the numbers as
prose. Three things follow from that, and all three actually happened:

- **The checks get rewritten every session, differently.** Whether a run is comparable to the last one
  becomes a matter of reading two transcripts.
- **The checks have bugs, and a throwaway check takes its bugs with it.** Building this folder found
  three in one afternoon: a `-is [DBNull]` guard that missed the `$null` the SQL Server driver
  actually returns, a set of failure patterns where `convert|int` matched three of four messages
  including the `int` inside `constraint`, and a Badges import missing the `-ColumnMap` the demo
  passes. Each read as a defect in the repository for a few minutes.
- **A recorded number can stop being true without anyone noticing.** On 2026-08-16 entry 10's
  *"0 differences on every column"* turned out not to reproduce. Prose cannot fail; a script can.

## Running it

Everything needs the containers up — `start_demo.ps1`, or `04_docker_compose.sh` if you are an agent
and must not sit in an interactive shell.

```powershell
# everything, about ten to fifteen minutes
.\verify\Invoke-Verify.ps1

# one scenario
.\verify\Invoke-Verify.ps1 -Only 06

# with a report file per script, so a long run can be watched from another window
.\verify\Invoke-Verify.ps1 -ReportFolder C:\tmp\verify
```

A single script can be run on its own and takes the same `-ReportPath`:

```powershell
.\verify\02_stackexchange.ps1 -ReportPath C:\tmp\stackexchange.txt
```

**Why a report file exists at all:** PowerShell holds redirected output until the process exits, so
`... > out.txt` shows nothing while a run is in progress. `-ReportPath` writes with `AutoFlush`, which
matters for the two scripts that take minutes.

## What each script covers

| Script | Reproduces | Notes |
| --- | --- | --- |
| `01_timesheets.ps1` | 94 rows from three `Department*.xlsx`, 3 departments, 4 people | Seconds. SQL Server only. |
| `02_stackexchange.ps1` | `Users.xml` 12220 rows, 12179 with real milliseconds, 0 of 12220 differing on either timestamp column on all three providers with no tolerance | Minutes, mostly Oracle. Also covers `-ColumnMap` through Badges. |
| `03_geodata.ps1` | `countries.geojson` 14643643 bytes / 258 features, PostGIS 258/258 with 0 invalid | Minutes. The Oracle read-back is reported, **not** asserted — see below. |
| `04_photoservice.ps1` | 24 images, 43.5 MB, byte-identical by MD5 and length; the transfer's first pass carrying the backlog | Needs the shop running. |
| `05_projectstatus.ps1` | 9 rows → 8 after the heading → 4 rejected for 4 named reasons → 5 land after the colour retry → 3 handed back | Seconds. The only fully deterministic scenario. |
| `06_eventstreaming.ps1` | The five `Kfk` functions, `auto.offset.reset` three ways, one application generation on the topic, whole-millisecond timestamps, and the replay compared to PostgreSQL column by column | **Stops and starts the shop** — see below. |

## Three rules these scripts follow

**Drive the shipped function, do not reimplement it.** The point is to exercise `lib/`. Where a demo's
own helper is re-expressed — `Import-ProjectStatusRow` in 05, the transfer body in 04 — it is because
the original cannot be called (it is narration, or an infinite loop), and the comment says so. What it
drives underneath is always the shipped function.

**Assert the preconditions, or the comparison measures nothing.** Every value comparison here is
preceded by a check that there was something to compare: that 12179 of 12220 `LastAccessDate` values
really do carry milliseconds, that no photo is `NULL` before the MD5s are taken, that payment uuids
were actually compared so the fold was doing work. Three checks passed for the wrong reason in a
single session on 2026-08-15 — one compared failure counts while the membership moved, one compared
MD5 hashes that were `NULL` on both sides, one asserted a row count copied out of the documentation.
**Before adding a `Test-Fact`, ask what it would print if the thing under test were absent.**

**Do not assert a number nobody measured.** `AGENTS.md` records the known-good numbers; anything else
is printed rather than asserted. Two cases in particular:

- **Oracle's `SDO_UTIL.TO_WKTGEOMETRY` is non-deterministic on purpose.** It fails for a varying
  subset of the same 258 rows — seen at 31, 39, 40, 42 and 64 — and the sibling's `DIFFERENCES.md`
  lists four rejected explanations. `03_geodata.ps1` prints the count and asserts only that the
  failure is not total. Do not turn the printed number into an expected value.
- **The PhotoService transfer timings depend on how long the shop has been running.** `04` asserts the
  shape — the first pass carries the backlog, later passes do not — and prints the milliseconds.

## What they change

They create `Verify_*` tables and drop them again. Beyond that:

- `02_stackexchange.ps1` uses the shipped `Users` and `Badges` tables rather than copies, because the
  `DATETIME2(3)` and `TIMESTAMP(3)` column types are part of what is being checked, and truncates
  them at the end.
- `04_photoservice.ps1` loads the images into the PostgreSQL `photo` table. That is what demo 4's
  first section does and it leaves that table in its post-demo state.
- **`06_eventstreaming.ps1` stops the shop and starts it again.** Freezing the source is the only way
  to compare a replay against PostgreSQL without the two moving apart underneath. Starting it again
  truncates its tables and empties the topic, so demos 4 and 6 need their usual two minutes
  afterwards.

## Adding to it

One file per scenario, numbered to match `demo/NN_<name>.ps1`. `Verify-Common.ps1` holds the four
helpers and should stay the only shared file — six copies of a reporting helper is exactly the drift
this folder exists to prevent. None of it follows the `lib/` function contract; that contract is for
`lib/`, and these are runnable scripts.

The sibling repository has the same folder with the same six scenarios, so a number that changes on
one side can be checked on the other.
