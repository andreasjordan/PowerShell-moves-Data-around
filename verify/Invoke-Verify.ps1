# Runs every verify script and prints one summary line each.
#
# Each script is started as its own process, because they end in Complete-Verify, which calls exit -
# dot-sourcing them would end this one at the first summary.
#
# The whole run takes something like ten to fifteen minutes, most of it Oracle: 12220 rows in
# 02_stackexchange and 258 geometries one at a time in 03_geodata.

param (
    # A substring of the script name, so -Only 06 or -Only kafka runs just that one
    [string]$Only,

    # Where the per-script reports go. Each gets <name>.txt, written with AutoFlush so that a long
    # run can be watched from another window.
    [string]$ReportFolder
)

$ErrorActionPreference = 'Stop'

$scripts = @(Get-ChildItem -Path $PSScriptRoot/[0-9][0-9]_*.ps1 | Sort-Object Name)
if ($Only) { $scripts = @($scripts | Where-Object Name -like "*$Only*") }

if (-not $scripts) {
    Write-Host "No verify script matches [$Only]"
    exit 1
}

if ($ReportFolder -and -not (Test-Path -Path $ReportFolder)) {
    $null = New-Item -Path $ReportFolder -ItemType Directory
}

$results = foreach ($script in $scripts) {
    Write-Host ''
    Write-Host "################ $($script.Name) ################"

    $arguments = @('-NoProfile', '-File', $script.FullName)
    if ($ReportFolder) {
        $arguments += @('-ReportPath', (Join-Path $ReportFolder ($script.BaseName + '.txt')))
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & pwsh @arguments
    $stopwatch.Stop()

    [PSCustomObject]@{
        Script  = $script.Name
        Passed  = $LASTEXITCODE -eq 0
        Seconds = [int]$stopwatch.Elapsed.TotalSeconds
    }
}

Write-Host ''
Write-Host '################ summary ################'
foreach ($result in $results) {
    Write-Host ('{0}  {1,-28} {2,5} s' -f $(if ($result.Passed) { 'PASS' } else { 'FAIL' }), $result.Script, $result.Seconds)
}

$failed = @($results | Where-Object { -not $_.Passed })
Write-Host ''
if ($failed) {
    Write-Host "$($failed.Count) of $($results.Count) verify scripts reported a failure"
    exit 1
}
Write-Host "all $($results.Count) verify scripts passed"
exit 0
