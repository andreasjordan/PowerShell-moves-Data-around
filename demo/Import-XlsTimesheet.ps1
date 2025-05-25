function Import-XlsTimesheet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Path,
        [switch]$EnableException
    )

    try {
        Write-PSFMessage -Level Verbose -Message "Getting Excel timesheets from $Path"

        $files = Get-ChildItem -Path $Path
        foreach ($file in $files) {
            Write-PSFMessage -Level Verbose -Message "Importing file $($file.FullName)"

            $sheets = Get-ExcelSheetInfo -Path $file.FullName
            foreach ($sheet in $sheets) {
                Write-PSFMessage -Level Verbose -Message "Importing worksheet $($sheet.Name)"

                $rows = Import-Excel -Path $file.FullName -WorksheetName $sheet.Name -StartRow 3 -AsDate date, time_from, time_to -DataOnly
                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        Department = $file.BaseName
                        Person     = $sheet.Name
                        Start      = $row.date.AddHours($row.time_from.TimeOfDay.TotalHours)
                        End        = $row.date.AddHours($row.time_to.TimeOfDay.TotalHours)
                        Project    = $row.project
                        Task       = $row.task
                    }
                }
            }
        }
    } catch {
        Stop-PSFFunction -Message "Getting Excel timesheets failed: $($_.Exception.Message)" -EnableException $EnableException
    }
}
