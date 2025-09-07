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
    echo '{"expected_before": 0, "events": []}'
    exit 0
fi

# Stop the container on the host where it was found
ts_ns=$(ssh "$largest_host" bash -c "'
    docker stop \"$largest_container\" >/dev/null
    date +%s%N
'")

# Compute values
expected_before=$(( num_nodes * 512 ))
expected=$(( (num_nodes - 1) * 512 ))

# Output JSON in new schema
jq -n \
    --arg t "$ts_ns" \
    --argjson b "$expected_before" \
    --argjson e "$expected" \
    '{expected_before: $b, events: [ {timestamp_ns: ($t|tonumber), expected: $e} ]}'
