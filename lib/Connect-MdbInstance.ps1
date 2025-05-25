function Connect-MdbInstance {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [string]$Database = 'admin',
        [string]$Collection,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating connection to [$Instance]"

    $username = [uri]::EscapeDataString($Credential.UserName)
    $password = [uri]::EscapeDataString($Credential.GetNetworkCredential().Password)

    $connectParams = @{
        ConnectionString   = 'mongodb://{0}:{1}@{2}/{3}?authSource={3}' -f $username, $password, $Instance, $Database
        DatabaseName       = $Database
        ClientVariable     = 'mdbClient'
        DatabaseVariable   = 'mdbDatabase'
        CollectionVariable = 'mdbCollection'
    }
    if ($Collection) {
        $connectParams.CollectionName = $Collection
    }

    try {
        Write-PSFMessage -Level Verbose -Message "Opening connection"
        Connect-Mdbc @connectParams

        Write-PSFMessage -Level Verbose -Message "Returning connection object"
        [PSCustomObject]@{
            Client     = $mdbClient
            Database   = $mdbDatabase
            Collection = $mdbCollection
        }
    } catch {
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -EnableException $EnableException
    }
}
