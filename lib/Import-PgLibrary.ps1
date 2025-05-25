function Import-PgLibrary {
    [CmdletBinding()]
    param (
        [string[]]$Path = $PSScriptRoot,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Importing library from path: $($Path -join ', ')"

    $library = @(
        @{
            Package = 'Npgsql'
            LibPath = 'lib\net8.0\Npgsql.dll'
        }
        @{
            Package = 'Microsoft.Extensions.Logging.Abstractions'
            LibPath = 'lib\net9.0\Microsoft.Extensions.Logging.Abstractions.dll'
        }
    )

    try {
        if ($Path -match '\.dll$') {
            Add-Type -Path ($Path -match '\.dll$')
        } else {
            foreach ($lib in $library) {
                $libPath = "$($Path[0])\$($lib.LibPath -replace '^.*\\([^\\]+)$', '$1')"
                if (-not (Test-Path -Path $libPath)) {
                    Write-PSFMessage -Level Verbose -Message "Nuget package '$($lib.Package)' has to be downloaded"
                    $tmpFile = (New-TemporaryFile).FullName
                    $tmpFolder = $tmpFile -replace '.{4}$'
                    Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/$($lib.Package)" -OutFile $tmpFile -UseBasicParsing
                    Expand-Archive -Path $tmpFile -DestinationPath $tmpFolder
                    Move-Item -Path "$tmpFolder\$($lib.LibPath)" -Destination $libPath
                    Remove-Item -Path $tmpFile
                    Remove-Item -Path $tmpFolder -Recurse -Force
                }
                Add-Type -Path $libPath
            }
        }
    } catch {
        Stop-PSFFunction -Message "Import failed: $($_.Exception.InnerException.Message)" -Target $Path -EnableException $EnableException
    }
}
