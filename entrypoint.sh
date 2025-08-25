#!/bin/sh
set -e

echo "Starting resource tracker..."
sh /record_resources.sh &

echo "Starting generator..."
/usr/local/bin/generator/generator &

echo "Starting monoceros..."
/usr/local/bin/monoceros/monoceros #&

# echo "Starting Prometheus..."
# exec /bin/prometheus \
#   --config.file=/etc/prometheus/prometheus.yml \
#   --storage.tsdb.path=/prometheus
