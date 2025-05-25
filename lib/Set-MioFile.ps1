function Set-MioFile {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [string]$Key,
        [string]$Content,
        [string]$InFile,
        [string]$ContentType = 'text/plain; charset=UTF-8',
        [switch]$EnableException
    )

    if (-not $PSBoundParameters.ContainsKey('InFile')) {
        $InFile = (New-TemporaryFile).FullName
        Set-Content -Path $InFile -Value $Content -Encoding UTF8
    }

    $invokeParams = $Connection.SetFileParams($ContentType, $Key, $InFile)
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    $null = Invoke-WebRequest @invokeParams -Verbose:$false

    if (-not $PSBoundParameters.ContainsKey('InFile')) {
        Remove-Item -Path $InFile
    }
}
