function Get-MioFileList {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [switch]$EnableException
    )

    $invokeParams = $Connection.GetFileListParams()
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    $result = Invoke-WebRequest @invokeParams -Verbose:$false
    ([xml]$result.Content).ListBucketResult.Contents | Select-Object -Property Key, @{ n = 'LastModified' ; e = { [datetime]::ParseExact($_.LastModified, "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime() } }, ETag, Size
}
