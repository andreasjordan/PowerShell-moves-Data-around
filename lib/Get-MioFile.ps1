function Get-MioFile {
    [CmdletBinding()]
    Param(
        [PSCustomObject]$Connection,
        [string]$Key,
        [string]$OutFile,
        [string]$ContentType = 'text/plain; charset=UTF-8',
        [switch]$EnableException
    )

    if (-not $PSBoundParameters.ContainsKey('OutFile')) {
        $OutFile = (New-TemporaryFile).FullName
    }

    $invokeParams = $Connection.GetFileParams($ContentType, $Key, $OutFile)
    Write-PSFMessage -Level Verbose -Message $($invokeParams | ConvertTo-Json -Compress)
    $null = Invoke-WebRequest @invokeParams -Verbose:$false

    if (-not $PSBoundParameters.ContainsKey('OutFile')) {
        Get-Content -Path $OutFile -Encoding UTF8
        Remove-Item -Path $OutFile
    }
}
