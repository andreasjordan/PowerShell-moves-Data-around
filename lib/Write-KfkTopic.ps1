function Write-KfkTopic {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][object]$Connection,
        [Parameter(Mandatory)][string]$Topic,
        [object[]]$Data,
        [string]$Key,
        [int]$BatchSize = 1000,
        [switch]$EnableException
    )

    if (-not $Data) {
        Stop-PSFFunction -Message "No data is used, so there is nothing to do." -EnableException $EnableException
        return
    }

    Write-PSFMessage -Level Verbose -Message "Producing to topic $Topic"

    # Like Write-MdbCollection there is no target schema to ask about, and unlike a collection
    # there is not even a document model: a topic is a sequence of bytes with no idea what is in
    # them. Whatever goes in has to be serialized by whoever sends it, and this repository sends
    # JSON. -Depth 9 matches Write-MdbCollection and the demos, because the events nest.

    Write-Progress -Id 1 -Activity "Producing messages to $Topic"
    try {
        $rowCount = $Data.Count
        $completed = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($row in $Data) {
            $message = [Confluent.Kafka.Message[string, string]]::new()
            if ($Key) {
                $message.Key = "$($row.$Key)"
            }
            $message.Value = $row | ConvertTo-Json -Depth 9 -Compress

            # Produce only queues the message. The callback overload is the asynchronous one, and
            # passing $null means we do not want to be told about each delivery - the Flush below
            # is what proves they arrived.
            $Connection.Produce($Topic, $message, $null)
            $completed++

            if ($completed % $BatchSize -eq 0) {
                $progressParam = @{
                    Id       = 1
                    Activity = "Producing messages to $Topic"
                    Status   = "$completed of $rowCount messages produced"
                }
                if ($completed -gt 0) {
                    $progressParam.SecondsRemaining = $stopwatch.Elapsed.TotalSeconds * ($rowCount - $completed) / $completed
                }
                if ($rowCount -gt 0) {
                    $progressParam.PercentComplete = [Math]::Min(100, $completed * 100 / $rowCount)
                }
                if ($stopwatch.Elapsed.TotalSeconds -gt 1) {
                    $progressParam.CurrentOperation = "$([int]($completed / $stopwatch.Elapsed.TotalSeconds)) messages per second"
                }
                Write-Progress @progressParam
            }
        }

        # Nothing has necessarily reached the broker until this returns
        Write-PSFMessage -Level Verbose -Message "Flushing"
        $remaining = $Connection.Flush([timespan]::FromSeconds(30))
        if ($remaining -gt 0) {
            throw "$remaining messages were still queued after the flush timed out"
        }

        $stopwatch.Stop()
        Write-PSFMessage -Level Verbose -Message "Finished producing in $($stopwatch.ElapsedMilliseconds) Milliseconds"
    } catch {
        Stop-PSFFunction -Message "Producing to topic failed: $($_.Exception.Message)" -Target $Topic -EnableException $EnableException
        return
    } finally {
        Write-Progress -Id 1 -Activity x -Completed
    }
}
