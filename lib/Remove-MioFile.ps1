function Remove-MioFile {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [string]$Key,
        [switch]$EnableException
    )

    $invokeParams = $Connection.RemoveFileParams($Key)
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    try {
        $null = Invoke-WebRequest @invokeParams -Verbose:$false
    } catch {
        Stop-PSFFunction -Message "Removing file failed: $($_.Exception.Message)" -Target $Key -EnableException $EnableException
        return
    }
}
