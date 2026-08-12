#!/bin/bash

# Start SQL Server in the background
/opt/mssql/bin/sqlservr &
PID=$!

echo "Waiting for SQL Server to be available..."

# Wait until SQL Server is ready
# MSSQL_SA_PASSWORD is the password this container was started with, so it is already right here
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "SELECT 1" &> /dev/null; do
  echo "Waiting..."
  sleep 2
done

echo "Connected to SQL Server."

/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /init-scripts/timesheets.sql
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /init-scripts/stackexchange.sql
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /init-scripts/geodata.sql
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /init-scripts/photoservice.sql
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /init-scripts/projectstatus.sql

echo "SQL Server configuration complete."

# Bring SQL Server back to foreground (this replaces the shell script process with SQL Server)
wait $PID
