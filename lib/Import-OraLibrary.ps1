function Import-OraLibrary {
    [CmdletBinding()]
    param (
        [string[]]$Path = $PSScriptRoot,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Importing library from path: $($Path -join ', ')"

    $library = @(
        @{
            Package = 'Oracle.ManagedDataAccess.Core'
            LibPath = 'lib\netstandard2.1\Oracle.ManagedDataAccess.dll'
        }
    )

    try {
        if ($Path -match '\.dll$') {
            try {
                Add-Type -Path ($Path -match '\.dll$')
            } catch [System.Reflection.ReflectionTypeLoadException] {
                # Can be ignored
            }
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
                try {
                    Add-Type -Path $libPath
                } catch [System.Reflection.ReflectionTypeLoadException] {
                    # Can be ignored
                }
            }
        }
    } catch {
        Stop-PSFFunction -Message "Import failed: $($_.Exception.InnerException.Message)" -Target $Path -EnableException $EnableException
    }
}
