function Read-KfkTopic {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)][object]$Connection,
        [Parameter(Mandatory)][string]$Topic,
        [int]$First,
        [int]$Timeout = 5,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Subscribing to topic $Topic"

    # Every other read function in lib/ asks a question and gets an answer. A topic has no end,
    # so this one needs a stopping rule instead: -First messages, or -Timeout seconds with
    # nothing new. That is not a shortcut, it is what reading a log is - and against a topic
    # somebody is still writing to, only -First is guaranteed to return.
    try {
        $Connection.Subscribe($Topic)

        if ($First) {
            Write-PSFMessage -Level Verbose -Message "Reading, stopping after $First messages"
        } else {
            Write-PSFMessage -Level Verbose -Message "Reading, stopping after $Timeout seconds without a message"
        }

        $count = 0
        while ($true) {
            $result = $Connection.Consume([timespan]::FromSeconds($Timeout))
            if ($null -eq $result) {
                break
            }

            $result.Message.Value | ConvertFrom-Json
            $count++

            if ($First -and $count -ge $First) {
                break
            }
        }

        Write-PSFMessage -Level Verbose -Message "Retrieved $count messages"
    } catch {
        Stop-PSFFunction -Message "Reading topic failed: $($_.Exception.Message)" -Target $Topic -EnableException $EnableException
        return
    }
}
