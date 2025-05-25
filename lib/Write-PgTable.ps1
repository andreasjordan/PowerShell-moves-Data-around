function Write-PgTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][Npgsql.NpgsqlConnection]$Connection,
        [Parameter(Mandatory)][string]$Table,
        [object[]]$Data,
        [object]$DataReader,
        [int]$DataReaderRowCount,
        [int]$BatchSize = 1000,
        [switch]$TruncateTable,
        [Npgsql.NpgsqlTransaction]$Transaction,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Importing data into $Table"

    Write-PSFMessage -Level Verbose -Message "Getting target schema table"
    Write-Progress -Id 1 -Activity "Getting target schema table for $Table"
    try {
        $command = $Connection.CreateCommand()
        $command.CommandText = "SELECT * FROM $Table"
        if ($Transaction) {
            $command.Transaction = $Transaction
        }
        $reader = $command.ExecuteReader()
        $targetSchemaTable = $reader.GetSchemaTable()
    } catch {
        if ($PSBoundParameters.Keys -contains 'DataReader') { $DataReader.Dispose() }
        Stop-PSFFunction -Message "Getting target schema table failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
        return
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($command) { $command.Dispose() }
    }

    Write-PSFMessage -Level Verbose -Message "Initializing insert"
    Write-Progress -Id 1 -Activity "Initializing insert for $Table"
    try {
        $command = $Connection.CreateCommand()
        $command.CommandText = "SELECT * FROM $Table WHERE 1=0"
        if ($Transaction) {
            $command.Transaction = $Transaction
        }
        $command.CommandTimeout = 0
        $dataAdapter = [Npgsql.NpgsqlDataAdapter]::new($command)
        $null = [Npgsql.NpgsqlCommandBuilder]::new($dataAdapter)
        $dataTable = [System.Data.DataTable]::new()
        $null = $dataAdapter.Fill($dataTable)
    } catch {
        Stop-PSFFunction -Message "Initializing failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
        return
    }

    if ($TruncateTable) {
        Write-PSFMessage -Level Verbose -Message "Truncating table"
        Write-Progress -Id 1 -Activity "Truncating table"
        try {
            $command = $Connection.CreateCommand()
            $command.CommandText = "TRUNCATE TABLE $Table"
            if ($Transaction) {
                $command.Transaction = $Transaction
            }
            $null = $command.ExecuteNonQuery()
            $command.Dispose()
        } catch {
            if ($PSBoundParameters.Keys -contains 'DataReader') { $DataReader.Dispose() }
            Stop-PSFFunction -Message "Truncating table failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
            return
        } finally {
            if ($command) { $command.Dispose() }
        }
    }

    if ($PSBoundParameters.Keys -contains 'Data') {
        Write-PSFMessage -Level Verbose -Message "Filling data table and inserting rows"
        Write-Progress -Id 1 -Activity "Filling data table for $Table"
        try {
            $rowCount = $Data.Count
            $completed = 0
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            foreach ($row in $Data) {
                $newRow = $dataTable.NewRow()
                foreach ($column in $targetSchemaTable) {
                    $value = $row.$($column.ColumnName)
                    if ($null -ne $value) {
                        $newRow[$column.ColumnName] = $value
                    } 
                }
                $dataTable.Rows.Add($newRow)
                $completed++

                if ($completed % $BatchSize -eq 0) {
                    $null = $dataAdapter.Update($dataTable)
                    $dataTable.Clear()
        
                    $progressParam = @{ 
                        Id               = 1
                        Activity         = "Inserting rows into $Table"
                        Status           = "$completed of $rowCount rows transfered"
                        PercentComplete  = $completed * 100 / $rowCount
                        SecondsRemaining = $stopwatch.Elapsed.TotalSeconds * ($rowCount - $completed) / $completed
                    }
                    if ($stopwatch.Elapsed.TotalSeconds -gt 1) {
                        $progressParam.CurrentOperation = "$([int]($completed / $stopwatch.Elapsed.TotalSeconds)) rows per second"
                    }
                    Write-Progress @progressParam
                }
            }
            $null = $dataAdapter.Update($dataTable)
            $stopwatch.Stop()
            Write-PSFMessage -Level Verbose -Message "Finished import in $($stopwatch.ElapsedMilliseconds) Milliseconds"
        } catch {
            Stop-PSFFunction -Message "Filling data table failed: $($_.Exception.Message)" -Target $row -EnableException $EnableException
            return
        } finally {
            Write-Progress -Id 1 -Activity x -Completed
        }
    } elseif ($PSBoundParameters.Keys -contains 'DataReader') {
        try {
            $rowCount = $DataReaderRowCount
            $completed = 0
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while($DataReader.Read()) {
                $newRow = $dataTable.NewRow()
                foreach ($column in $targetSchemaTable) {
                    $newRow[$column.ColumnName] = $DataReader.GetValue($DataReader.GetOrdinal($column.ColumnName))
                }
                $dataTable.Rows.Add($newRow)
                $completed++
    
                if ($completed % $BatchSize -eq 0) {
                    $null = $dataAdapter.Update($dataTable)
                    $dataTable.Clear()
        
                    $progressParam = @{ 
                        Id               = 1
                        Activity         = "Inserting rows into $Table"
                        Status           = "$completed of $rowCount rows transfered"
                        PercentComplete  = $completed * 100 / $rowCount
                        SecondsRemaining = $stopwatch.Elapsed.TotalSeconds * ($rowCount - $completed) / $completed
                    }
                    if ($stopwatch.Elapsed.TotalSeconds -gt 1) {
                        $progressParam.CurrentOperation = "$([int]($completed / $stopwatch.Elapsed.TotalSeconds)) rows per second"
                    }
                    Write-Progress @progressParam
                }
            }
            $null = $dataAdapter.Update($dataTable)
            $DataReader.Dispose()
            $stopwatch.Stop()
            Write-PSFMessage -Level Verbose -Message "Finished import in $($stopwatch.ElapsedMilliseconds) Milliseconds"
        } catch {
            Stop-PSFFunction -Message "???? failed: $($_.Exception.Message)" -EnableException $EnableException
            return
        } finally {
            Write-Progress -Id 1 -Activity x -Completed
        }
    } else {
        Stop-PSFFunction -Message "Neither Data nor DataReader is used, so nothing to do." -EnableException $EnableException
        return
    }
}
