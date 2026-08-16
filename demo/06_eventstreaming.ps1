break
# This script needs PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

# Demo 4 asked "how do you know what changed?" and answered it three times: compare MAX(id),
# compare updated_at, or let Change Data Capture write it down for you. All three have the same
# shape - they stand at the target, look at the source, and work out the difference. Nobody ever
# asked the application what it did.
#
# This demo does. The PhotoService shop knows perfectly well when it added a customer - it is the
# thing that added them - and it can say so, once, on a log that anybody may read at their own speed.
#
# GIVE THE SHOP TWO MINUTES BEFORE RUNNING THIS. docker/photoservice-app.ps1 truncates its tables
# and empties the topic when it starts, and then staggers its work: a customer every six seconds,
# the first order after 60, the first payment after 90, the first shipment after 120. Run this
# straight after "docker compose up -d" and the topic holds nothing but "Added customer",
# order_event is empty, and every count below is zero - not because anything is broken, but
# because nothing has happened yet. "docker compose logs -f photoservice" shows how far along it is.
#
# The topic being emptied too is what keeps the log and the database describing the same run. It
# used to survive, and because the application restarts its ids at 1, three restarts left three
# customers with id 1 on the topic and the replay at the end of this script died on a primary key
# violation.

$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_photoservice.ps1

# Some code to save code in the script
$PSDefaultParameterValues = @{
    'Invoke-SqlQuery:Connection' = $photoservice.SqlConnection
    'Write-SqlTable:Connection'  = $photoservice.SqlConnection
    'Invoke-PgQuery:Connection'  = $photoservice.PgConnection
}



###########################################
# Before Kafka: you may already have an outbox #
###########################################


# There is a table in this database that nothing in demos 1 to 5 has ever read.
#
# order_event gets a row every time an order is paid for or shipped, written by the thing that did
# the paying and the shipping rather than worked out afterwards by comparing two databases.
#
# And it is written in the same transaction as the change itself - one BeginTransaction around the
# UPDATE order_header and the INSERT INTO order_event, in docker/photoservice-app.ps1. That is what
# makes an outbox trustworthy rather than merely convenient: the row and the thing it describes
# commit together, so there is no window in which the order is paid for and nothing says so.
#
# It is worth pointing at, because it is the part people leave out. Two autocommitted statements
# look identical in every demo and differ only on the day the process dies between them - and this
# application did exactly that until 2026-08-16.

Invoke-PgQuery -Query 'SELECT * FROM order_event ORDER BY id DESC LIMIT 5' | Format-Table

# That is a perfectly good pattern and it needs no new infrastructure at all. It is also where its
# limits are easiest to see:
#
# * You poll it. The reader asks every few seconds whether anything is new. Nothing pushes.
# * Deleting is your problem. Rows stay until somebody removes them, and removing them is only safe
#   once every reader is past them - so the table has to know about its readers.
# * A second reader changes the design. One consumer can delete as it goes. Two cannot, and now you
#   need a per-reader position, which is a table of offsets you have to write yourself.
#
# Kafka is what that turns into when you keep solving those three problems. The log keeps the
# messages, each reader keeps its own position in it, and nobody deletes anything on anybody's behalf.



##############################
# The same events, on a topic #
##############################


# The application produces an event whenever something actually happens - a customer, an order
# header, its details, a payment, a shipment. Scheduling chatter is printed and not sent.
#
# Two connect functions, because Kafka has no single connection: producing and consuming are
# different clients. This demo only consumes.

# A group that has read before carries on where it stopped, which is right for a consumer and
# wrong for a demo that gets stepped through again and again. So each run gets its own groups and
# therefore its own clean start.
$run = Get-Date -Format 'HHmmss'

$consumer = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId "look-$run" -FromBeginning

$events = Read-KfkTopic -Connection $consumer -Topic $photoservice.KfkTopic -First 5

$events[0] | ConvertTo-Json -Depth 5

# A timestamp, where it came from, what happened, and the details of what happened. Details is the
# object the application was working with at that moment - not a row of a table, and not a diff
# against anything.
#
# Note what the types did on the way. JSON has no date, no decimal and no GUID, so the sender
# decides how they travel - the same question MongoDB asked with Decimal128 and the same answer.
# ConvertFrom-Json turns the timestamp back into a [datetime] by itself, and a [guid] went out as
# an object rather than a string, which is why the replay below reads .PaymentUuid.Guid.

$events | Format-Table Timestamp, Component, Message



####################################
# Replaying the events into SQL Server #
####################################


# This is the loop demo 4 used to run against a bucket of log archives. Every message says what
# happened, so the consumer only has to know what each kind of event means: three of them are rows
# to insert, two are updates to an order that already exists.

# Dropped first, because this script is built to be stepped through again. A new run invents a new
# group id, so the consumer starts at the beginning of the topic - and replaying those events into
# tables that still hold them is a primary key violation, not a demo.
Invoke-SqlQuery -Query 'DROP TABLE IF EXISTS dbo.customer'
Invoke-SqlQuery -Query 'DROP TABLE IF EXISTS dbo.order_header'
Invoke-SqlQuery -Query 'DROP TABLE IF EXISTS dbo.order_detail'
Invoke-SqlQuery -Query 'CREATE TABLE dbo.customer (id INT, firstname VARCHAR(50), surname VARCHAR(50), city VARCHAR(50), email VARCHAR(200), CONSTRAINT customer_pk PRIMARY KEY (id))'
Invoke-SqlQuery -Query 'CREATE TABLE dbo.order_header (id INT, customer_id INT, created_at DATETIME2, updated_at DATETIME2, payment_uuid UNIQUEIDENTIFIER, shipment_uuid UNIQUEIDENTIFIER, CONSTRAINT order_header_pk PRIMARY KEY (id))'
Invoke-SqlQuery -Query 'CREATE TABLE dbo.order_detail (order_id INT, photo_id INT, quantity INT, price NUMERIC(7, 2), CONSTRAINT order_detail_pk PRIMARY KEY (order_id, photo_id))'

$countQuery = 'SELECT (SELECT COUNT(*) FROM dbo.customer) AS customers, (SELECT COUNT(*) FROM dbo.order_header) AS orders, (SELECT COUNT(*) FROM dbo.order_detail) AS details'

# A helper defined in the demo rather than in lib/, so it does not follow the lib/ function
# contract - no EnableException, no Stop-PSFFunction. It is part of the story, not of the library:
# what each kind of event means is the thing this demo is about.
function Invoke-LoggingEvent {
    param ([PSCustomObject]$LoggingEvent)

    $details = $LoggingEvent.Details

    switch ($LoggingEvent.Message) {
        'Added customer' {
            Write-SqlTable -Table dbo.customer -Data $details
        }
        'Added order header' {
            Write-SqlTable -Table dbo.order_header -Data $details
        }
        'Added order details' {
            # The only event whose Details is a list - one order, many lines
            Write-SqlTable -Table dbo.order_detail -Data $details
        }
        'Added payment' {
            Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, payment_uuid = @payment_uuid WHERE id = @id' -ParameterValues @{
                updated_at   = $details.UpdatedAt
                payment_uuid = [guid]$details.PaymentUuid.Guid
                id           = $details.OrderId
            }
        }
        'Added shipment' {
            Invoke-SqlQuery -Query 'UPDATE dbo.order_header SET updated_at = @updated_at, shipment_uuid = @shipment_uuid WHERE id = @id' -ParameterValues @{
                updated_at    = $details.UpdatedAt
                shipment_uuid = [guid]$details.ShipmentUuid.Guid
                id            = $details.OrderId
            }
        }
    }
}

# The consumer reads from where it last stopped, applies what it gets, and then counts what is in
# the target. -First 60 is the stopping rule, and a log needs one - it has no end of its own.
#
# This consumer's group was created with -FromBeginning, so it began at the start of the topic
# rather than at its end - though it is five messages in by now, because the section above already
# read that many. The shop has been running for a while, so there is a backlog, and it works
# through it 60 at a time.
$events = Read-KfkTopic -Connection $consumer -Topic $photoservice.KfkTopic -First 60
foreach ($loggingEvent in $events) { Invoke-LoggingEvent -LoggingEvent $loggingEvent }
"applied $($events.Count) events"

Invoke-SqlQuery -Query $countQuery | Format-Table


# NOW RUN THOSE FOUR LINES AGAIN.
#
# "applied 60 events" again, and the totals climb. Two numbers doing two different jobs:
#
# * "applied ..." is the increment - what this one call did. It says exactly 60 because 60 is the
#   cap and there is still a backlog behind it. Once the consumer catches up with the end of the
#   topic it drops to a handful: whatever the shop managed while you were reading this. Measured:
#   the shop produces about 3.5 events a second, so 60 per press only gains ground if the presses
#   come closer together than every 17 seconds - read this paragraph aloud between two of them and
#   the backlog wins.
# * The counts are totals in the target. They only ever go up, because that is what a target does.
#
# That is the offset at work. The consumer committed its position as it read, so each call starts
# where the last one stopped. It is catching up, one bite at a time, and nothing is re-read or
# skipped. How far behind it is has a name - lag - and Redpanda Console shows it per group.
#
# Compare that with demo 4, where every transfer began by asking SQL Server for MAX(id). Here
# nobody asked the target anything; the consumer already knew.



#################################################
# And now the part a database comparison cannot do #
#################################################


# The events are still on the topic. They were not consumed away - reading is not taking.
#
# So a reader that has never read before can have the whole history, in order, and build the target
# from nothing. GroupId is what Kafka remembers a reader by, so a name nobody has used is a reader
# with no past.

# The tables have rows in them from the run above, and replaying an insert onto a row that is
# already there is a primary key violation. Replay is only worth anything if applying an event
# twice is safe - here that is bought the blunt way, by starting from empty.
#
# Emptying the target is only half of it, though, and the other half is upstream: the topic has to
# hold each id once. It does because the application empties it at startup, when it also restarts
# those ids at 1. Leave the topic to accumulate across restarts and no amount of truncating here
# saves you - the duplicates are in the log itself.
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.customer'
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_header'
Invoke-SqlQuery -Query 'TRUNCATE TABLE dbo.order_detail'

$replay = Connect-KfkConsumer -Instance $photoservice.KfkInstance -GroupId "replay-$run" -FromBeginning

# Where does "the whole topic" end? The shop is still producing, so the answer is a moving target -
# and this is the high watermark, the offset one past the last message the broker has right now.
# Without it, "read everything" means "read forever" and this script never comes back.
$partition = [Confluent.Kafka.TopicPartition]::new($photoservice.KfkTopic, 0)
$watermark = $replay.QueryWatermarkOffsets($partition, [timespan]::FromSeconds(10))
$messageCount = $watermark.High.Value - $watermark.Low.Value
"the topic holds $messageCount messages"

$events = Read-KfkTopic -Connection $replay -Topic $photoservice.KfkTopic -First $messageCount
"read $($events.Count) of them"


# Applying the history one event at a time would be one round trip per event, and there are
# thousands. But the whole history is in hand, so it can be folded first: a payment and a shipment
# only set columns on an order that is already here, so they are applied to the row in memory
# rather than as an UPDATE against the database. What is left is three bulk inserts.
#
# Having the history is exactly what makes that possible. The incremental transfer above could not
# do it - it only ever saw the next sixty events.
$customers = [System.Collections.ArrayList]::new()
$headers = [ordered]@{ }
$lines = [System.Collections.ArrayList]::new()

foreach ($loggingEvent in $events) {
    $details = $loggingEvent.Details
    switch ($loggingEvent.Message) {
        'Added customer'      { $null = $customers.Add($details) }
        'Added order header'  { $headers[[string]$details.id] = $details }
        'Added order details' { $null = $lines.AddRange(@($details)) }
        'Added payment' {
            $header = $headers[[string]$details.OrderId]
            if ($header) {
                $header.updated_at = $details.UpdatedAt
                $header.payment_uuid = [guid]$details.PaymentUuid.Guid
            }
        }
        'Added shipment' {
            $header = $headers[[string]$details.OrderId]
            if ($header) {
                $header.updated_at = $details.UpdatedAt
                $header.shipment_uuid = [guid]$details.ShipmentUuid.Guid
            }
        }
    }
}

if ($customers.Count) { Write-SqlTable -Table dbo.customer -Data $customers.ToArray() }
if ($headers.Count)   { Write-SqlTable -Table dbo.order_header -Data @($headers.Values) }
if ($lines.Count)     { Write-SqlTable -Table dbo.order_detail -Data $lines.ToArray() }

Invoke-SqlQuery -Query $countQuery | Format-Table

# The target was rebuilt from the log alone. Nobody queried PostgreSQL to do it - the only thing
# this script ever asked PostgreSQL was what order_event looked like, right at the start.
#
# That is the argument for streaming, and it is not "it is faster". It is that the history is a
# thing that exists, so a new reader can be added later and still catch up, and a target that gets
# corrupted can be thrown away and rebuilt.
#
# Two honest caveats:
#
# * Order is per partition. One partition here, so the header arrives before its details. Spread
#   the topic over several and that guarantee is per key, not per topic - which is why an order id
#   is the obvious key.
# * -FromBeginning is not a rewind. It sets auto.offset.reset, which only applies to a group that
#   has no committed offset. Passing it to a group that has read before changes nothing. This is
#   the single most confusing thing about Kafka for anybody new to it, and the replay above works
#   because the group name is new every time.



####################
# Looking at the topic #
####################


# Redpanda Console is at http://127.0.0.1:8080 - the topic, the messages, and the consumer groups
# with their current offsets, including the throwaway ones this script has been creating.
#
# It is there for the same reason pgAdmin is: during a talk it is easier to point at.



###########
# Cleanup #
###########


Invoke-SqlQuery -Query 'DROP TABLE dbo.customer'
Invoke-SqlQuery -Query 'DROP TABLE dbo.order_header'
Invoke-SqlQuery -Query 'DROP TABLE dbo.order_detail'

$consumer.Close()
$consumer.Dispose()
$replay.Close()
$replay.Dispose()



<####################################################################################################

Key takeaways:

* Three of the four ways to know what changed compare the target against the source. The fourth is
  the application saying what it did, and it is the only one that does not have to guess.
* If you already write an outbox table, you already have events. Kafka is what that becomes once you
  want more than one reader and stop wanting to delete rows.
* Reading is not taking. The messages stay, each reader keeps its own position, and a new reader
  gets the whole history.
* Replay is only useful if applying an event twice is safe. Deciding that is the work; the transport
  is not.
* Holding the whole history lets you fold it before you write. Thousands of updates collapsed into
  three bulk inserts, because a payment only changes a row that was already in hand.
* JSON has no date, no decimal and no GUID, so the sender decides how they travel. That is the same
  lesson as Decimal128 in MongoDB and the milliseconds in Oracle.

####################################################################################################>
