function Remove-KfkTopic {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$Topic,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Removing topic $Topic on instance [$Instance]"

    # The counterpart of Remove-MdbCollection, and docker/photoservice-app.ps1 calls the two next
    # to each other. The application restarts its ids at 1 every time it starts, so a topic that
    # outlives the tables ends up holding several customers with id 1 - and demo 6 replays all of
    # them into one primary key.
    #
    # What this does not throw away is the history demo 6 is about. That history is across
    # readers, not across application starts: a new group id still replays the whole topic, and
    # the offsets that make it work are per group.

    # -Instance rather than -Connection, unlike Remove-MdbCollection. Deleting a topic is neither
    # producing nor consuming, so neither of the two clients Connect-Kfk* returns is the right
    # thing to hand over - see the note in Connect-KfkProducer about why there are two of them.
    $configuration = [System.Collections.Generic.Dictionary[string, string]]::new()
    $configuration['bootstrap.servers'] = $Instance

    try {
        $adminClient = [Confluent.Kafka.AdminClientBuilder]::new($configuration).Build()

        # The whole topic list, not GetMetadata($Topic, ...) - asking about one topic by name is
        # enough to create it on a broker with auto-creation on, which is the state of this lab.
        if ($adminClient.GetMetadata([timespan]::FromSeconds(10)).Topics.Topic -notcontains $Topic) {
            Write-PSFMessage -Level Verbose -Message "Topic $Topic does not exist, so there is nothing to do"
            return
        }

        $adminClient.DeleteTopicsAsync([string[]]@($Topic)).GetAwaiter().GetResult()

        # The broker acknowledges the request before the topic is actually gone, and the caller's
        # next message would simply recreate it - so wait for it to disappear rather than race it.
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            if ($adminClient.GetMetadata([timespan]::FromSeconds(10)).Topics.Topic -notcontains $Topic) {
                Write-PSFMessage -Level Verbose -Message "Removed topic $Topic"
                return
            }
            Start-Sleep -Milliseconds 500
        }
        throw "topic $Topic was still there 30 seconds after it was deleted"
    } catch {
        Stop-PSFFunction -Message "Removing topic failed: $($_.Exception.InnerException.Message)" -Target $Topic -EnableException $EnableException
        return
    } finally {
        if ($adminClient) { $adminClient.Dispose() }
    }
}
