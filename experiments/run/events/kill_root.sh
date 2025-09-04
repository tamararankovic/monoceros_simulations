#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
shift  # remove num_nodes from args
hosts=("$@")

largest_container=""
largest_host=""

# First, find the container with the largest name across all hosts
for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    if [[ -z "$containers" ]]; then
        continue
    fi
    for c in $containers; do
        if [[ -z "$largest_container" || "$c" > "$largest_container" ]]; then
            largest_container="$c"
            largest_host="$host"
        fi
    done
done

if [[ -z "$largest_container" ]]; then
    echo '{"host": "", "container_name": "", "timestamp_ns": null}'
    exit 0
fi

# Stop the container on the host where it was found
ts_ns=$(ssh "$largest_host" bash -c "'
    docker stop \"$largest_container\" >/dev/null
    date +%s%N
'")

# Output: host, container_name, timestamp_ns, expected before, expected after
jq -n \
    --arg h "$largest_host" \
    --arg c "$largest_container" \
    --arg t "$ts_ns" \
    --argjson n "$num_nodes" \
    '{host: $h, container_name: $c, timestamp_ns: ($t|tonumber),
      expected_before: ($n * 512),
      expected_after: (($n - 1) * 512)}'
