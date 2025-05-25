function Remove-MdbCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][PSCustomObject]$Connection,
        [string]$Collection,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Removing collection $Collection"

    Write-PSFMessage -Level Verbose -Message "Getting target collection"
    if ($Collection) {
        $mdbCollection = Get-MdbcCollection -Database $Connection.Database -Name $Collection
        # Collection will be created if it does not exist
    } else {
        $mdbCollection = $Connection.Collection
        $Collection = $mdbCollection.CollectionNamespace.CollectionName
    }

    try {
        Remove-MdbcCollection -Name $Collection -Database $Connection.Database
    } catch {
        Stop-PSFFunction -Message "Removing collection failed: $($_.Exception.Message)" -Target $Collection -EnableException $EnableException
    }
}
