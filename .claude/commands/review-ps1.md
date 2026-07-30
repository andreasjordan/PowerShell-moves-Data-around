---
description: Repo-specific PowerShell review for lib/, demo/ and the setup scripts
---

Review $ARGUMENTS. If no argument is given, review the working diff against `main`; if that is empty,
review `lib/`.

Read `AGENTS.md` first. This is a teaching repository, not production code, and a generic review of it
produces mostly false positives.

## Do not report

These are deliberate. Reporting them is noise:

- The hard-coded password `Passw0rd!` and the hard-coded `127.0.0.1`
- `ConvertTo-SecureString -AsPlainText -Force` and plaintext password parameters
- Missing tests, missing CI, missing module manifest
- Missing `ShouldProcess` / `-WhatIf` on state-changing verbs
- "Use dbatools instead of hand-written ADO.NET"
- `System.Data.SqlClient` instead of `Microsoft.Data.SqlClient`
- Unused variables, repeated re-imports and `Format-Table` / `Out-GridView` calls in `demo/*.ps1`
- The bare `break` on line 1 of the numbered demo scripts
- Missing comment-based help

## Do report, in this order

1. **Sibling divergence.** The `Sql`, `Ora` and `Pg` implementations of a verb family are meant to be
   near-identical. A parameter, default value, guard clause or `finally` block present in one and
   missing in another is a finding unless the provider genuinely requires it.
2. **`$_.Exception.InnerException.Message` in a `try` block that only calls cmdlets.** It is correct for
   .NET method calls, which PowerShell wraps in a `MethodInvocationException`, but a cmdlet failure has
   no wrapper, so `InnerException` is null and the message renders with no cause at all.
3. **Missing `return` after `Stop-PSFFunction`** in a multi-step function, so execution continues into
   code that assumes the failed step succeeded.
4. **Resources not disposed on every path** — a missing or incomplete `finally` around a command,
   reader or stream.
5. **Operator precedence, null and length bugs** — `-not $x -like $y`, `.Substring()` on a possibly
   shorter string, `.Count` on a scalar, `-eq $null` on the wrong side.
6. **Demo or setup scripts that dot-source `lib/` without `Import-Module PSFramework` first**, relying
   on module auto-loading.
7. **Drift between the docs and the code** — `README.md`, `AGENTS.md`, `lib/README.md` and
   `data/*/README.md` versus what the scripts actually do.
8. **PSScriptAnalyzer findings** under `./PSScriptAnalyzerSettings.psd1`. Run it and cite the rule name.

## Rules

- Verify each finding by reading the code before reporting it. Say what concrete input or state
  produces the wrong behaviour.
- Do not run any container, WSL command or `demo/` script.
- Report findings only. Do not edit files unless explicitly asked to afterwards.
