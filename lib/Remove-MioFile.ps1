function Remove-MioFile {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [string]$Key,
        [switch]$EnableException
    )

    $invokeParams = $Connection.RemoveFileParams($Key)
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    $null = Invoke-WebRequest @invokeParams -Verbose:$false
}
