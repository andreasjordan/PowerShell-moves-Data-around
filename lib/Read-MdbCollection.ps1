function Read-MdbCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][PSCustomObject]$Connection,
        [string]$Collection,
        [object]$Filter,
        [Int64]$First,
        [Int64]$Last,
        [Int64]$Skip,
        [object]$Project,
        [object]$Sort,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Reading collection $Collection"

    Write-PSFMessage -Level Verbose -Message "Getting collection"
    if ($Collection) {
        $mdbCollection = Get-MdbcCollection -Database $Connection.Database -Name $Collection
        # Collection will be created if it does not exist
    } else {
        $mdbCollection = $Connection.Collection
        $Collection = $mdbCollection.CollectionNamespace.CollectionName
    }

    $params = @{
        Collection = $mdbCollection
        As         = 'PSCustomObject'
    }
    if ($PSBoundParameters.ContainsKey('Filter')) {
        $params.Filter = $Filter
    }
    if ($PSBoundParameters.ContainsKey('First')) {
        $params.First = $First
    }
    if ($PSBoundParameters.ContainsKey('Last')) {
        $params.Last = $Last
    }
    if ($PSBoundParameters.ContainsKey('Skip')) {
        $params.Skip = $Skip
    }
    if ($PSBoundParameters.ContainsKey('Project')) {
        $params.Project = $Project
    }
    if ($PSBoundParameters.ContainsKey('Sort')) {
        $params.Sort = $Sort
    }
    
    try {
        Get-MdbcData @params
    } catch {
        Stop-PSFFunction -Message "Reading collection failed: $($_.Exception.Message)" -Target $Collection -EnableException $EnableException
    }
}
