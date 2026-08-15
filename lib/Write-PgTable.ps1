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

    if ($PSBoundParameters.Keys -contains 'Data') {
        # COPY names the columns it is about to receive, and for objects that is every column of the
        # target: a property the object does not have becomes NULL, as the filled DataTable used to.
        $copyColumnNames = $targetSchemaTable.Rows.ColumnName
        $rowCount = $Data.Count
    } elseif ($PSBoundParameters.Keys -contains 'DataReader') {
        Write-PSFMessage -Level Verbose -Message "Getting source schema table"
        Write-Progress -Id 1 -Activity "Getting source schema table"
        try {
            $sourceSchemaTable = $DataReader.GetSchemaTable()
        } catch {
            $DataReader.Dispose()
            Stop-PSFFunction -Message "Getting source schema table failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
            return
        }
        # Here COPY names the source columns instead, in the reader's own order, so a row can be
        # written straight out of the reader. The match is case insensitive and that is load bearing:
        # PostgreSQL folds its identifiers to lower case while an Oracle source hands out upper case.
        $copyColumnNames = foreach ($sourceColumnName in $sourceSchemaTable.Rows.ColumnName) {
            $targetColumnName = $targetSchemaTable.Rows.ColumnName | Where-Object { $_ -eq $sourceColumnName }
            if ($null -eq $targetColumnName) {
                $DataReader.Dispose()
                Stop-PSFFunction -Message "No target column for source column $sourceColumnName found." -Target $Table -EnableException $EnableException
                return
            }
            Write-PSFMessage -Level Verbose -Message "Adding column mapping: $sourceColumnName -> $targetColumnName"
            $targetColumnName
        }
        $rowCount = $DataReaderRowCount
    } else {
        Stop-PSFFunction -Message "Neither Data nor DataReader is used, so nothing to do." -EnableException $EnableException
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

    Write-PSFMessage -Level Verbose -Message "Initializing copy"
    Write-Progress -Id 1 -Activity "Initializing copy for $Table"
    try {
        # COPY is what PostgreSQL itself offers for bulk loading, and it is the counterpart of the
        # SqlBulkCopy and OracleBulkCopy the two sibling functions use. The text format hands every
        # value over as text and lets the server parse it into the column type, so there is no type
        # handling on this side at all. A copy on this connection joins an open transaction by
        # itself, which is why $Transaction is not passed anywhere here.
        $copyCommand = "COPY $Table ($($copyColumnNames -join ', ')) FROM STDIN"
        Write-PSFMessage -Level Verbose -Message "Starting copy with [$copyCommand]"
        $writer = $Connection.BeginTextImport($copyCommand)
        $writer.Timeout = 0
    } catch {
        if ($PSBoundParameters.Keys -contains 'DataReader') { $DataReader.Dispose() }
        Stop-PSFFunction -Message "Initializing copy failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
        return
    }

    Write-PSFMessage -Level Verbose -Message "Copying rows"
    Write-Progress -Id 1 -Activity "Inserting rows into $Table"
    try {
        $completed = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        if ($PSBoundParameters.Keys -contains 'Data') {
            foreach ($row in $Data) {
                $values = foreach ($columnName in $copyColumnNames) {
                    # The property access is case insensitive, and that is load bearing rather than
                    # incidental - see the comment in Import-PgTable, the names in $copyColumnNames
                    # come folded from PostgreSQL while the object's are whatever the source called them
                    $value = $row.$columnName
                    if ($null -eq $value -or $value -is [DBNull]) {
                        '\N'
                    } elseif ($value -is [datetime]) {
                        # "$value" renders a DateTime without its milliseconds, so this one is explicit.
                        # Numbers are safe: PowerShell converts those culture invariantly.
                        $value.ToString('o')
                    } elseif ($value -is [byte[]]) {
                        # Doubled on purpose: bytea wants the text \x0001, but \x is also an escape
                        # of the copy format itself, so a single backslash would hand PostgreSQL the
                        # raw bytes instead of the text - and byte 0x00 then fails as invalid UTF8
                        '\\x' + [System.Convert]::ToHexString($value)
                    } else {
                        # The backslash goes first, or the escapes written after it get escaped again
                        "$value".Replace('\', '\\').Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r')
                    }
                }
                # Not WriteLine: on Windows that ends the line with CRLF and leaves a carriage
                # return on the last value of every row
                $writer.Write(($values -join "`t") + "`n")
                $completed++

                if ($completed % $BatchSize -eq 0) {
                    $progressParam = @{
                        Id       = 1
                        Activity = "Inserting rows into $Table"
                        Status   = "$completed of $rowCount rows transfered"
                    }
                    if ($completed -gt 0) {
                        $progressParam.SecondsRemaining = $stopwatch.Elapsed.TotalSeconds * ($rowCount - $completed) / $completed
                    }
                    if ($rowCount -gt 0) {
                        # The row count can be too low, so we have to make sure we stay inside of the allowed range
                        $progressParam.PercentComplete = [Math]::Min(100, $completed * 100 / $rowCount)
                    }
                    if ($stopwatch.Elapsed.TotalSeconds -gt 1) {
                        $progressParam.CurrentOperation = "$([int]($completed / $stopwatch.Elapsed.TotalSeconds)) rows per second"
                    }
                    Write-Progress @progressParam
                }
            }
        } else {
            while ($DataReader.Read()) {
                $values = for ($ordinal = 0; $ordinal -lt $DataReader.FieldCount; $ordinal++) {
                    $value = $DataReader.GetValue($ordinal)
                    if ($null -eq $value -or $value -is [DBNull]) {
                        '\N'
                    } elseif ($value -is [datetime]) {
                        $value.ToString('o')
                    } elseif ($value -is [byte[]]) {
                        '\\x' + [System.Convert]::ToHexString($value)
                    } else {
                        "$value".Replace('\', '\\').Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r')
                    }
                }
                $writer.Write(($values -join "`t") + "`n")
                $completed++

                if ($completed % $BatchSize -eq 0) {
                    $progressParam = @{
                        Id       = 1
                        Activity = "Inserting rows into $Table"
                        Status   = "$completed of $rowCount rows transfered"
                    }
                    if ($completed -gt 0) {
                        $progressParam.SecondsRemaining = $stopwatch.Elapsed.TotalSeconds * ($rowCount - $completed) / $completed
                    }
                    if ($rowCount -gt 0) {
                        # The row count can be too low, so we have to make sure we stay inside of the allowed range
                        $progressParam.PercentComplete = [Math]::Min(100, $completed * 100 / $rowCount)
                    }
                    if ($stopwatch.Elapsed.TotalSeconds -gt 1) {
                        $progressParam.CurrentOperation = "$([int]($completed / $stopwatch.Elapsed.TotalSeconds)) rows per second"
                    }
                    Write-Progress @progressParam
                }
            }
        }
        # Disposing the writer is what completes the copy, and what surfaces a server side error
        $writer.Dispose()
        $stopwatch.Stop()
        Write-PSFMessage -Level Verbose -Message "Finished import in $($stopwatch.ElapsedMilliseconds) Milliseconds"
    } catch {
        # A copy that is neither completed nor cancelled leaves the connection in COPY mode, and
        # every later command on it fails with something that says nothing about this one
        try { $writer.Cancel() } catch { Write-PSFMessage -Level Verbose -Message "Cancelling the copy failed: $($_.Exception.Message)" }
        Stop-PSFFunction -Message "Copying rows failed: $($_.Exception.InnerException.Message)" -Target $Table -EnableException $EnableException
        return
    } finally {
        if ($PSBoundParameters.Keys -contains 'DataReader') { $DataReader.Dispose() }
        Write-Progress -Id 1 -Activity x -Completed
    }
}
