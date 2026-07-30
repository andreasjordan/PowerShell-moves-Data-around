function Get-MioFileList {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [switch]$EnableException
    )

    $invokeParams = $Connection.GetFileListParams()
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    try {
        $result = Invoke-WebRequest @invokeParams -Verbose:$false
    } catch {
        Stop-PSFFunction -Message "Getting file list failed: $($_.Exception.Message)" -Target $Connection.Bucket -EnableException $EnableException
        return
    }
    ([xml]$result.Content).ListBucketResult.Contents | Select-Object -Property Key, @{ n = 'LastModified' ; e = { [datetime]::ParseExact($_.LastModified, "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime() } }, ETag, Size
}
