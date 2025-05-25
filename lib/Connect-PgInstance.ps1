function Connect-PgInstance {
    [CmdletBinding()]
    [OutputType([Npgsql.NpgsqlConnection])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [string]$Database,
        [switch]$PooledConnection,
        [switch]$EnableException
    )

    if ($Instance -match '^([^:]+):(\d+)$') {
        $pgHost = $Matches[1]
        $pgPort = $Matches[2]
    } else {
        $pgHost = $Instance
        $pgPort = 5432
    }

    Write-PSFMessage -Level Verbose -Message "Creating connection to host [$pgHost] on port [$pgPort]"

    $csb = [Npgsql.NpgsqlConnectionStringBuilder]::new()
    $csb.Host = $pgHost
    $csb.Port = $pgPort
    $csb.Username = $Credential.UserName
    $csb.Password = $Credential.GetNetworkCredential().Password
    if ($Database) {
        $csb.Database = $Database
    }
    if ($PooledConnection) {
        Write-PSFMessage -Level Verbose -Message "Using connection pooling"
        $csb.Pooling = $true
    } else {
        Write-PSFMessage -Level Verbose -Message "Disabling connection pooling"
        $csb.Pooling = $false
    }
    # Is this maybe needed in some cases?
    # $csb.Encoding = 'UTF8'   # To be able to use UTF8 data

    $connection = [Npgsql.NpgsqlConnection]::new($csb.ConnectionString)

    try {
        Write-PSFMessage -Level Verbose -Message "Opening connection"
        $connection.Open()
        
        Write-PSFMessage -Level Verbose -Message "Returning connection object"
        $connection
    } catch {
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -Target $connection -EnableException $EnableException
    }
}
