function Write-MdbCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][PSCustomObject]$Connection,
        [string]$Collection,
        [object[]]$Data,
        [ScriptBlock]$Convert,
        [Object]$Id,
        [Object[]]$Property,
        [switch]$TruncateCollection,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Importing data into $Collection"

    Write-PSFMessage -Level Verbose -Message "Getting target collection"
    if ($Collection) {
        $mdbCollection = Get-MdbcCollection -Database $Connection.Database -Name $Collection
        # Collection will be created if it does not exist
    } else {
        $mdbCollection = $Collection.Collection
        $Collection = $mdbCollection.CollectionNamespace.CollectionName
    }

    if ($TruncateCollection) {
        Write-PSFMessage -Level Verbose -Message "Truncating collection"
        Remove-MdbcCollection -Name $Collection -Database $Connection.Database
        $mdbCollection = Get-MdbcCollection -Database $Connection.Database -Name $Collection
    }

    $addDataParams = @{
        Collection = $mdbCollection 
        Many       = $true
    }
    if ($PSBoundParameters.ContainsKey('Convert')) {
        $addDataParams.Convert = $Convert
    }
    if ($PSBoundParameters.ContainsKey('Id')) {
        $addDataParams.Id = $Id
    }
    if ($PSBoundParameters.ContainsKey('Property')) {
        $addDataParams.Property = $Property
    }

    try {
        Write-PSFMessage -Level Verbose -Message "Importing $($Data.Count) rows"
        $Data | Add-MdbcData @addDataParams
        Write-PSFMessage -Level Verbose -Message "Import finished"
    } catch {
        Stop-PSFFunction -Message "Importing data failed: $($_.Exception.Message)" -Target $Collection -EnableException $EnableException
    }
}
