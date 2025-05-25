#!/bin/bash

# Start MinIO server in the background
minio server --console-address ":9001" /data/minio &
MINIO_PID=$!

echo "Waiting for MinIO to be available..."

# Wait until MinIO is ready
until mc alias set minio http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do
  echo "Waiting..."
  sleep 2
done

echo "Connected to MinIO."

# Create buckets
mc mb minio/photoservice --ignore-existing
mc mb minio/stackexchange --ignore-existing

# Create policies from files
mc admin policy create minio photoservice-fullaccess /etc/minio/init/policy-photoservice.json
mc admin policy create minio stackexchange-fullaccess /etc/minio/init/policy-stackexchange.json

# Create users
mc admin user add minio photoservice "Passw0rd!"
mc admin user add minio stackexchange "Passw0rd!"

# Attach policies to users
mc admin policy attach minio photoservice-fullaccess --user photoservice
mc admin policy attach minio stackexchange-fullaccess --user stackexchange

echo "MinIO configuration complete."

# Bring MinIO back to foreground (this replaces the shell script process with MinIO)
wait $MINIO_PID
