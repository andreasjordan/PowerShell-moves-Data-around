function Import-KfkLibrary {
    [CmdletBinding()]
    param (
        [string[]]$Path = $PSScriptRoot,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Importing library from path: $($Path -join ', ')"

    # Two packages rather than one, which is what makes this different from Import-PgLibrary and
    # Import-OraLibrary. Those two load a managed assembly and nothing else. Confluent.Kafka is a
    # thin wrapper: the Kafka protocol is spoken by the native librdkafka in a second package, and
    # the .NET loader only finds it in the same directory as the managed assembly.
    #
    # This directory is shared by three platforms - Windows runs the demos, WSL2 runs
    # 06_test_connections.ps1, and the photoservice container mounts it read only. The native file
    # is named differently on each (librdkafka.dll against librdkafka.so), so both can sit here at
    # once and each platform downloads its own the first time it is used. Which is also why the
    # two downloads are guarded separately: finding the managed assembly says nothing about
    # whether this platform's native is here.
    #
    # Forward slashes throughout, because this runs on Linux as well and a backslash is an
    # ordinary character in a path there.
    # On Linux the package offers three builds and the plain one is the wrong one: it links
    # libsasl2.so.3, while Ubuntu ships libsasl2.so.2, so it cannot be loaded here at all. The
    # centos8 build has everything linked in and needs nothing but glibc - which is why no apt
    # package has to be installed in WSL2 or in the photoservice container. It is copied to the
    # name the runtime looks for.
    $managedFile = 'Confluent.Kafka.dll'
    $managedPath = 'lib/net8.0/Confluent.Kafka.dll'
    if ($IsWindows) {
        $nativeFile = 'librdkafka.dll'
        $nativePath = 'runtimes/win-x64/native'
        $nativeSource = '*.dll'
    } else {
        $nativeFile = 'librdkafka.so'
        $nativePath = 'runtimes/linux-x64/native'
        $nativeSource = 'centos8-librdkafka.so'
    }

    try {
        if ($Path -match '\.dll$') {
            Add-Type -Path ($Path -match '\.dll$')
            return
        }

        $managedTarget = "$($Path[0])/$managedFile"
        if (-not (Test-Path -Path $managedTarget)) {
            Write-PSFMessage -Level Verbose -Message "Nuget package 'Confluent.Kafka' has to be downloaded"
            $tmpFile = (New-TemporaryFile).FullName
            $tmpFolder = $tmpFile -replace '.{4}$'
            Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Confluent.Kafka' -OutFile $tmpFile -UseBasicParsing
            Expand-Archive -Path $tmpFile -DestinationPath $tmpFolder
            Move-Item -Path "$tmpFolder/$managedPath" -Destination $managedTarget
            Remove-Item -Path $tmpFile
            Remove-Item -Path $tmpFolder -Recurse -Force
        }

        if (-not (Test-Path -Path "$($Path[0])/$nativeFile")) {
            Write-PSFMessage -Level Verbose -Message "Nuget package 'librdkafka.redist' has to be downloaded for $nativePath"
            $tmpFile = (New-TemporaryFile).FullName
            $tmpFolder = $tmpFile -replace '.{4}$'
            Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/librdkafka.redist' -OutFile $tmpFile -UseBasicParsing
            Expand-Archive -Path $tmpFile -DestinationPath $tmpFolder
            if ($IsWindows) {
                # Every file, not just librdkafka itself: it needs the OpenSSL, zlib and zstd
                # libraries next to it
                Get-ChildItem -Path "$tmpFolder/$nativePath" -Filter $nativeSource -File |
                    Move-Item -Destination $Path[0] -Force
            } else {
                Move-Item -Path "$tmpFolder/$nativePath/$nativeSource" -Destination "$($Path[0])/$nativeFile" -Force
            }
            Remove-Item -Path $tmpFile
            Remove-Item -Path $tmpFolder -Recurse -Force
        }

        # Nothing loads the native library explicitly. The runtime finds it next to the managed
        # assembly on both platforms, and Confluent.Kafka's own Library::Load is worse than
        # useless here - it reaches librdkafka through libdl, which Ubuntu 24.04 no longer ships
        # as a separate library, so asking for it by full path fails where doing nothing works.
        Add-Type -Path $managedTarget
    } catch {
        Stop-PSFFunction -Message "Import failed: $($_.Exception.Message)" -Target $Path -EnableException $EnableException
    }
}
