# The four helpers every verify script uses, in one file so that six copies cannot drift apart.
#
# This is the one shared file in verify/ and it should stay the only one. It is dot-sourced, so the
# functions land in the calling script's scope and $script: below is that script's scope - which is
# what keeps the counters per run rather than global.
#
# None of this follows the lib/ function contract. That contract is for lib/, and these are helpers
# of a runnable script - no EnableException, no Stop-PSFFunction, and Write-Host on purpose, because
# the output of a verify run is meant to be read by a person.

function Start-Verify {
    param (
        [Parameter(Mandatory)][string]$Name,
        [string]$ReportPath
    )

    $script:verifyName = $Name
    $script:verifyPass = 0
    $script:verifyFail = 0
    $script:verifyWriter = $null

    # A report file is optional, and it exists because PowerShell holds redirected output until the
    # process exits - so "verify.ps1 > out.txt" shows nothing at all while a long run is in
    # progress, and the Geodata and StackExchange runs take minutes. AutoFlush is the whole point.
    if ($ReportPath) {
        $script:verifyWriter = [System.IO.StreamWriter]::new($ReportPath, $false)
        $script:verifyWriter.AutoFlush = $true
    }

    Write-VerifyLine ''
    Write-VerifyLine "=== verify: $Name ==="
    Write-VerifyLine ''
}

function Write-VerifyLine {
    param ([string]$Text)

    Write-Host $Text
    if ($script:verifyWriter) { $script:verifyWriter.WriteLine($Text) }
}

# A fact is one thing that is either true of the running system or is not. The -Detail is not
# decoration: it is what tells you whether a PASS passed for the right reason, so it should carry
# the number that was compared rather than the word "ok".
function Test-Fact {
    param (
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Ok,
        [string]$Detail
    )

    if ($Ok) { $script:verifyPass++ } else { $script:verifyFail++ }
    Write-VerifyLine ('{0}  {1}{2}' -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  -- $Detail" } else { '' }))
}

function Complete-Verify {
    Write-VerifyLine ''
    Write-VerifyLine "=== $($script:verifyName): $($script:verifyPass) passed, $($script:verifyFail) failed ==="

    if ($script:verifyWriter) {
        $script:verifyWriter.Close()
        $script:verifyWriter = $null
    }

    # The exit code is what lets Invoke-Verify.ps1 report a total without parsing this output
    exit $(if ($script:verifyFail) { 1 } else { 0 })
}
