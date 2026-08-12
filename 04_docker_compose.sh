#!/bin/bash

set -e

cd ./docker

# The demo password. Docker Compose reads this file for the container environment, and it happens
# to be valid shell as well, so the waits below can use the same value instead of repeating it.
# Careful: the CREATE USER statements in the init SQL still have the password as a literal, so
# changing it here alone is not enough.
. ./.env

# 02_wsl2_setup.sh starts docker, but 01_setup.ps1 shuts WSL2 down right after that, and
# start_demo.ps1 runs after a reboot - so in both cases the daemon has to come up again.
# It usually does, because systemd starts it, but "usually" is a race right after WSL2 boots.
service docker start >/dev/null 2>&1 || true

echo "Waiting for the docker daemon..."

for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Once more, this time without hiding the error, so a daemon that never came up says why
docker info >/dev/null

# Stop the sibling repository's containers, if they are running
#
# Both repositories publish the same ports, so only one stack runs at a time. That much would show
# up as a bind error - but the passwords and the database names are the same too, so the other
# stack answers every connection a demo or 06_test_connections.ps1 makes. A run that starts while
# the sibling's containers are up therefore does not fail, it succeeds against the wrong volumes.
#
# The filter is the label docker compose sets itself, so nothing here needs a file from the other
# repository - which matters, because a clone of this one does not have it.
#
# "stop" and not "down": the sibling's volumes survive, so switching back is one start_demo.ps1
# and none of its data is gone.
SIBLING_PROJECT=python-moves-data-around

sibling_containers="$(docker ps --quiet --filter "label=com.docker.compose.project=$SIBLING_PROJECT")"
if [ -n "$sibling_containers" ]; then
    echo "Stopping the containers of $SIBLING_PROJECT - both repositories use the same ports"
    docker stop $sibling_containers >/dev/null
fi

docker compose up -d

# The steps that follow connect to the databases right away, but a container needs a while for
# its first start and the demo databases are created only after that. Without these waits,
# 06_test_connections.ps1 fails with a handshake error.
#
# There is no such failure today, and that is an accident rather than a design: 05_sample_data_setup.ps1
# spends minutes downloading sample data, which always gave the containers enough time. Skipping a
# download that is already there takes that away again.
#
# Each check asks for the database of a demo instead of just asking whether the server answers,
# because the databases are created after the server accepts connections. Reading the container
# log is not an alternative: "docker logs" keeps the output of earlier runs, so the message of a
# previous start would be found immediately - measured at one second, while the server was still
# starting. It looks like a fix and silently keeps the race.
#
# Ask for the database its init script creates *last*. ProjectStatus is the fifth and last one in
# sqlserver-init.sh, so waiting for TimeSheets would return while four databases were still missing.
#
# The first argument is the compose service name, which is also what you would type to look at it.

wait_for() {
    local service="$1"
    local attempts="$2"
    shift 2

    echo "Waiting for $service to create the demo databases..."

    for _ in $(seq 1 "$attempts"); do
        if "$@" 2>/dev/null | grep -q '^1$'; then
            echo "$service is ready"
            return 0
        fi

        # A container that has stopped is never going to answer, so say so now rather than
        # sitting out the whole timeout
        if [ -z "$(docker compose ps --status running --quiet "$service")" ]; then
            echo "$service has stopped" >&2
            break
        fi

        sleep 2
    done

    # The probe above throws its errors away, so without this a failure here explains nothing -
    # a container killed by its mem_limit looks exactly like one that is merely slow
    echo "$service is not ready, these are the last 50 lines of its log:" >&2
    docker compose logs --tail 50 "$service" >&2
    return 1
}

wait_for sqlserver 150 \
    docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -h -1 -W \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = 'ProjectStatus'"

# PostgreSQL runs the files in /docker-entrypoint-initdb.d in alphabetical order, so
# stackexchange.sql is the last of the three - but CREATE DATABASE is its *first* statement, so
# asking for the database would return while its 18 tables were still being created. Import_VoteTypes
# is the last table in that file, and PostgreSQL folds the name to lower case.
wait_for postgres 150 \
    docker compose exec -T postgres psql -U postgres -d stackexchange -tAc \
    "SELECT COUNT(*) FROM pg_tables WHERE tablename = 'import_votetypes'"

wait_for mongo 150 \
    docker compose exec -T mongo mongosh --quiet -u stackexchange -p "$PASSWORD" \
    --authenticationDatabase stackexchange stackexchange \
    --eval 'db.runCommand({ ping: 1 }).ok'

# Oracle needs a command of its own, because sqlplus takes its query on stdin and not as an
# argument. Connecting as the demo user is the check: while the startup scripts have not run,
# that user does not exist yet and sqlplus simply fails.
oracle_ready() {
    printf 'SET PAGESIZE 0 FEEDBACK OFF HEADING OFF\nSELECT COUNT(*) FROM user_tables WHERE table_name = '"'"'USERS'"'"';\nEXIT\n' \
        | docker compose exec -T oracle sqlplus -S "stackexchange/$PASSWORD@localhost/XEPDB1" \
        | tr -d '[:space:]'
}

# Oracle takes far longer to start than the other two, so it gets 15 minutes rather than 5
wait_for oracle 450 oracle_ready
