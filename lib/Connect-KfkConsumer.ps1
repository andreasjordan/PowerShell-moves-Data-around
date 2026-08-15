function Connect-KfkConsumer {
    [CmdletBinding()]
    [OutputType([Confluent.Kafka.IConsumer[string, string]])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$GroupId,
        [switch]$FromBeginning,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating consumer for instance [$Instance] in group [$GroupId]"

    # The counterpart of Connect-KfkProducer - see the note there about why there are two.

    # GroupId is what Kafka remembers a reader by. Two consumers in the same group share the work
    # and share one set of offsets; a consumer in a new group has never read anything.
    #
    # FromBeginning sets auto.offset.reset, and the name of that setting is worth reading
    # carefully: it only applies when the group has no committed offset yet. An existing group
    # continues where it left off no matter what is passed here, so "start again" means a new
    # group id and nothing else.
    $configuration = [System.Collections.Generic.Dictionary[string, string]]::new()
    $configuration['bootstrap.servers'] = $Instance
    $configuration['group.id'] = $GroupId
    $configuration['auto.offset.reset'] = if ($FromBeginning) { 'earliest' } else { 'latest' }

    try {
        $builder = [Confluent.Kafka.ConsumerBuilder[string, string]]::new($configuration)
        $consumer = $builder.Build()

        # See the note in Connect-KfkProducer: metadata belongs to the admin client in the .NET
        # client, and a dependent one borrows this consumer's connection
        Write-PSFMessage -Level Verbose -Message "Checking the connection"
        $adminClient = [Confluent.Kafka.DependentAdminClientBuilder]::new($consumer.Handle).Build()
        try {
            $null = $adminClient.GetMetadata([timespan]::FromSeconds(10))
        } finally {
            $adminClient.Dispose()
        }

        Write-PSFMessage -Level Verbose -Message "Returning consumer"
        $consumer
    } catch {
        if ($consumer) { $consumer.Dispose() }
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -Target $Instance -EnableException $EnableException
    }
}
