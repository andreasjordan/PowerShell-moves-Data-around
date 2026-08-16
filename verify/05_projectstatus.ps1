# Reproduces the ProjectStatus numbers from AGENTS.md: 9 rows after blanks are dropped, 8 after the
# "NEW PROJECTS:" heading is skipped, 4 rejected for 4 distinct reasons, 5 land after the colour
# retry, 3 handed back.
#
# This is the only scenario whose numbers are fully deterministic - the sample data is fixed and
# nothing is generated - so it is the one place where an exact count is a fair assertion.
#
# Needs SQL Server running. Creates dbo.Verify_ProjectStatus and drops it again.

param ([string]$ReportPath)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/Verify-Common.ps1

Start-Verify -Name 'ProjectStatus' -ReportPath $ReportPath

Push-Location -Path $PSScriptRoot/../demo
try {
    Import-Module -Name PSFramework, ImportExcel
    foreach ($file in (Get-ChildItem -Path ../lib/*-Sql*.ps1)) { . $file.FullName }

    $excelData = @(Import-Excel -Path ../data/projectstatus/ProjectStatus.xlsx -WorksheetName ProjectStatus -StartRow 3 -DataOnly)

    $nonBlank = @($excelData | Where-Object { $_.Title -ne '' })
    $toImport = @($nonBlank | Where-Object { $_.Title -notmatch ':$' })
    Test-Fact -Name '9 rows after the blank rows are dropped' -Ok ($nonBlank.Count -eq 9) -Detail "$($nonBlank.Count) rows"
    Test-Fact -Name '8 rows after the "NEW PROJECTS:" heading is skipped' -Ok ($toImport.Count -eq 8) -Detail "$($toImport.Count) rows"

    $credential = [PSCredential]::new('ProjectStatus', ('Passw0rd!' | ConvertTo-SecureString -AsPlainText -Force))
    $connection = Connect-SqlInstance -Instance 127.0.0.1 -Credential $credential -Database ProjectStatus

    Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE IF EXISTS dbo.Verify_ProjectStatus' -EnableException
    Invoke-SqlQuery -Connection $connection -EnableException -Query @'
CREATE TABLE dbo.Verify_ProjectStatus (
  Title            VARCHAR(50),
  Priority         VARCHAR(10),
  Manager          VARCHAR(50),
  Status           VARCHAR(50),
  Color            VARCHAR(10),
  ProgressPercent  INT,
  Milestone        VARCHAR(100),
  MilestoneDate    DATETIME2,
  CONSTRAINT Verify_ProjectStatus_PK PRIMARY KEY (Title),
  CONSTRAINT Verify_ProjectStatus_Priority CHECK (Priority IN ('Low', 'Medium', 'High')),
  CONSTRAINT Verify_ProjectStatus_Color CHECK (Color IN ('Green', 'Yellow', 'Red')),
  CONSTRAINT Verify_ProjectStatus_ProgressPercent CHECK (ProgressPercent >= 0 AND ProgressPercent <= 100)
)
'@

    # The demo's Import-ProjectStatusRow. It is demo narration rather than a lib/ function, so it is
    # re-expressed here; what it drives - Invoke-SqlQuery with -ParameterValues - is the shipped one.
    function Import-Row {
        param ($Row)
        $invokeParams = @{
            Connection      = $connection
            Query           = 'INSERT INTO dbo.Verify_ProjectStatus (Title, Priority, Manager, Status, Color, ProgressPercent, Milestone, MilestoneDate) ' +
                              'VALUES (@Title, @Priority, @Manager, @Status, @Color, @ProgressPercent, @Milestone, @MilestoneDate)'
            ParameterValues = @{
                Title           = $Row.Title
                Priority        = $Row.Priority
                Manager         = $Row.Manager
                Status          = $Row.Status
                Color           = $Row.Color
                ProgressPercent = $Row.ProgressPercent
                Milestone       = $Row.Milestone
                MilestoneDate   = $Row.MilestoneDate
            }
            EnableException = $true
        }
        Invoke-SqlQuery @invokeParams
    }

    try {
        # First pass, no fixing
        $failures = [ordered]@{ }
        foreach ($row in $toImport) {
            try { Import-Row -Row $row } catch { $failures[$row.Title] = "$_" }
        }

        $landed = Invoke-SqlQuery -Connection $connection -Query 'SELECT COUNT(*) FROM dbo.Verify_ProjectStatus' -As SingleValue -EnableException
        Test-Fact -Name '4 of the 8 rows are rejected' -Ok ($failures.Count -eq 4) -Detail "$($failures.Count) rejected: $(($failures.Keys) -join ', ')"
        Test-Fact -Name '4 rows land on the first pass' -Ok ($landed -eq 4) -Detail "$landed rows"

        # Naming the four reasons rather than counting them. AGENTS.md warns about exactly this:
        # comparing failure counts while the membership moves underneath is a check that passes for
        # the wrong reason, and it did once.
        # The patterns have to be precise enough to match one message each. A first attempt used
        # "convert|int", which matched "converting", "Conversion" and the "int" inside
        # "constraint" - three of the four messages, and it read as a pass.
        $reasons = [ordered]@{
            'a date that is not a date'        = 'converting date and/or time'
            'a Status longer than VARCHAR(50)' = 'would be truncated'
            'a colour the CHECK rejects'       = 'Verify_ProjectStatus_Color'
            'a word in an INT column'          = "to data type int"
        }
        foreach ($reason in $reasons.Keys) {
            $matched = @($failures.Values | Where-Object { $_ -match $reasons[$reason] })
            Test-Fact -Name "exactly one failure is $reason" -Ok ($matched.Count -eq 1) -Detail "$($matched.Count) message(s) match"
        }
        $distinct = @($failures.Values | ForEach-Object { $m = $_; ($reasons.Keys | Where-Object { $m -match $reasons[$_] } | Select-Object -First 1) } | Sort-Object -Unique)
        Test-Fact -Name 'the 4 failures are 4 distinct reasons' -Ok ($distinct.Count -eq 4) -Detail ($distinct -join ' | ')

        foreach ($title in $failures.Keys) { Write-VerifyLine "      rejected [$title]: $($failures[$title] -replace '\s+', ' ')" }

        # Second pass, with the colour retry the demo ends on
        Invoke-SqlQuery -Connection $connection -Query 'TRUNCATE TABLE dbo.Verify_ProjectStatus' -EnableException
        $excelData = @(Import-Excel -Path ../data/projectstatus/ProjectStatus.xlsx -WorksheetName ProjectStatus -StartRow 3 -DataOnly)
        $toImport = @($excelData | Where-Object { $_.Title -ne '' -and $_.Title -notmatch ':$' })

        $handedBack = 0
        $retried = 0
        foreach ($row in $toImport) {
            try {
                Import-Row -Row $row
            } catch {
                if ("$_" -match 'Verify_ProjectStatus_Color') {
                    $retried++
                    $row.Color = 'Red'
                    # A retry that fails again falls through to the hand-back below, which is what
                    # the demo does too - but say so rather than leaving an empty catch
                    try { Import-Row -Row $row ; continue } catch { Write-VerifyLine "      the colour retry also failed for [$($row.Title)]" }
                }
                $handedBack++
            }
        }

        $landed = Invoke-SqlQuery -Connection $connection -Query 'SELECT COUNT(*) FROM dbo.Verify_ProjectStatus' -As SingleValue -EnableException
        Test-Fact -Name 'exactly one row is retried, for its colour' -Ok ($retried -eq 1) -Detail "$retried retried"
        Test-Fact -Name '5 rows land after the colour retry' -Ok ($landed -eq 5) -Detail "$landed rows"
        Test-Fact -Name '3 rows are handed back' -Ok ($handedBack -eq 3) -Detail "$handedBack rows"

        # The retried row really is in the table, and really is Red. Without this the count above
        # could be reached by any five rows.
        $red = Invoke-SqlQuery -Connection $connection -Query "SELECT COUNT(*) FROM dbo.Verify_ProjectStatus WHERE Color = 'Red'" -As SingleValue -EnableException
        Test-Fact -Name 'the retried row is in the table as Red' -Ok ($red -ge 1) -Detail "$red row(s) are Red"
    } finally {
        Invoke-SqlQuery -Connection $connection -Query 'DROP TABLE IF EXISTS dbo.Verify_ProjectStatus'
        $connection.Close()
    }
} finally {
    Pop-Location
}

Complete-Verify
