function Get-OraDataReader {
    [CmdletBinding()]
    [OutputType([Oracle.ManagedDataAccess.Client.OracleDataReader])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Table')]
        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'Table')]
        [string]$Table,

        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [string]$Query,

        [Parameter(ParameterSetName = 'Query')]
        [System.Collections.IDictionary]$ParameterValues,

        [Parameter(ParameterSetName = 'Query')]
        [System.Collections.IDictionary]$ParameterTypes,

        [Parameter(ParameterSetName = 'Table')]
        [Parameter(ParameterSetName = 'Query')]
        [Oracle.ManagedDataAccess.Client.OracleTransaction]$Transaction,

        [Parameter(ParameterSetName = 'Table')]
        [Parameter(ParameterSetName = 'Query')]
        [Int32]$QueryTimeout = 600,

        [Parameter(ParameterSetName = 'Table')]
        [Parameter(ParameterSetName = 'Query')]
        [switch]$EnableException
    )

    if ($Table) {
        $Query = "SELECT * FROM $Table"
    }

    try {
        Write-PSFMessage -Level Verbose -Message "Getting data reader for [$Query]"
        $command = $Connection.CreateCommand()
        $command.CommandText = $Query
        if ($Transaction) {
            $command.Transaction = $Transaction
        }
        $command.CommandTimeout = $QueryTimeout
        if ($null -ne $ParameterValues) {
            Write-PSFMessage -Level Verbose -Message "Adding parameters to command"
            $command.BindByName = $true
            foreach ($parameterName in $ParameterValues.Keys) {
                $parameter = $command.CreateParameter()
                $parameter.ParameterName = $parameterName
                if (($null -ne $ParameterTypes) -and ($null -ne $ParameterTypes[$parameterName])) {
                    $parameter.OracleDbType = $ParameterTypes[$parameterName]
                } elseif ($ParameterValues[$parameterName].Length -gt 4000) {
                    $parameter.OracleDbType = 'CLOB'
                }
                $parameter.Value = $ParameterValues[$parameterName]
                if ($null -eq $parameter.Value) {
                    $parameter.Value = [DBNull]::Value
                }
                $null = $command.Parameters.Add($parameter)
            }
        }
        , $command.ExecuteReader()
    } catch {
        Stop-PSFFunction -Message "Getting data reader failed: $($_.Exception.InnerException.Message)" -Target $Query -EnableException $EnableException
    } finally {
        try { $command.Dispose() } catch { }
    }
}
