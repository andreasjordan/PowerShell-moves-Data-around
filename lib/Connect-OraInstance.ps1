function Connect-OraInstance {
    [CmdletBinding()]
    [OutputType([Oracle.ManagedDataAccess.Client.OracleConnection])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [switch]$AsSysdba,
        [switch]$PooledConnection,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating connection to instance [$Instance]"

    $csb = [Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder]::new()
    $csb['Data Source'] = $Instance
    $csb['User ID'] = $Credential.UserName
    $csb.Password = $Credential.GetNetworkCredential().Password
    if ($PooledConnection) {
        Write-PSFMessage -Level Verbose -Message "Using connection pooling"
        $csb.Pooling = $true
    } else {
        Write-PSFMessage -Level Verbose -Message "Disabling connection pooling"
        $csb.Pooling = $false
    }
    if ($AsSysdba) {
        Write-PSFMessage -Level Verbose -Message "Adding SYSDBA to connection string"
        $csb['DBA Privilege'] = 'SYSDBA'
    }
    $connection = [Oracle.ManagedDataAccess.Client.OracleConnection]::new($csb.ConnectionString)
    
    try {
        Write-PSFMessage -Level Verbose -Message "Opening connection"
        $connection.Open()
        
        Write-PSFMessage -Level Verbose -Message "Returning connection object"
        $connection
    } catch {
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -Target $connection -EnableException $EnableException
    }
}
