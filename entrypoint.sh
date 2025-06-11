#!/bin/sh
set -e

echo "Starting monoceros..."
/usr/local/bin/monoceros/monoceros &

echo "Starting generator..."
/usr/local/bin/generator/generator &

echo "Starting Prometheus..."
exec /bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus
