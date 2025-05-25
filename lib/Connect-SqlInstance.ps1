function Connect-SqlInstance {
    [CmdletBinding()]
    [OutputType([System.Data.SqlClient.SqlConnection])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [PSCredential]$Credential,
        [string]$Database,
        [switch]$PooledConnection,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating connection to instance [$Instance]"

    $csb = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $csb['Data Source'] = $Instance
    if ($Credential) {
        $csb['User ID'] = $Credential.UserName
        $csb.Password = $Credential.GetNetworkCredential().Password
    } else {
        $csb['Integrated Security'] = $true
    }
    $csb['Initial Catalog'] = $Database
    if ($PooledConnection) {
        Write-PSFMessage -Level Verbose -Message "Using connection pooling"
        $csb.Pooling = $true
    } else {
        Write-PSFMessage -Level Verbose -Message "Disabling connection pooling"
        $csb.Pooling = $false
    }
    $connection = [System.Data.SqlClient.SqlConnection]::new($csb.ConnectionString)

    try {
        Write-PSFMessage -Level Verbose -Message "Opening connection"
        $connection.Open()
        
        Write-PSFMessage -Level Verbose -Message "Returning connection object"
        $connection
    } catch {
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -Target $connection -EnableException $EnableException
    }
}
