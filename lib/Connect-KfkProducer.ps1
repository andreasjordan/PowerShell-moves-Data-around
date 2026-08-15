function Connect-KfkProducer {
    [CmdletBinding()]
    [OutputType([Confluent.Kafka.IProducer[string, string]])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating producer for instance [$Instance]"

    # There is no Connect-KfkInstance, and that is not an omission. Every other provider here has
    # one connection that reads and writes; Kafka has a producer and a consumer, which are
    # different clients with different configuration and nothing shared behind them.

    # Kafka calls this the bootstrap server: the broker that is asked where the others are.
    # There is only one here, so it answers with itself.
    $configuration = [System.Collections.Generic.Dictionary[string, string]]::new()
    $configuration['bootstrap.servers'] = $Instance

    try {
        $builder = [Confluent.Kafka.ProducerBuilder[string, string]]::new($configuration)
        $producer = $builder.Build()

        # Building a producer contacts nothing, the same way a MongoClient does not until the
        # first operation. Asking for the metadata forces it, so that a broker which is not
        # running fails here rather than somewhere later.
        #
        # The sibling simply calls producer.list_topics(). There is no such method here: in the
        # .NET client metadata belongs to the admin client, and a dependent one borrows the
        # producer's own connection rather than opening a second.
        Write-PSFMessage -Level Verbose -Message "Checking the connection"
        $adminClient = [Confluent.Kafka.DependentAdminClientBuilder]::new($producer.Handle).Build()
        try {
            $null = $adminClient.GetMetadata([timespan]::FromSeconds(10))
        } finally {
            $adminClient.Dispose()
        }

        Write-PSFMessage -Level Verbose -Message "Returning producer"
        $producer
    } catch {
        if ($producer) { $producer.Dispose() }
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -Target $Instance -EnableException $EnableException
    }
}
