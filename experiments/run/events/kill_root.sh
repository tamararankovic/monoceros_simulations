#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
shift  # remove num_nodes from args
hosts=("$@")

sum_nodes=$(( num_nodes * (num_nodes + 1) / 2 ))
curr_num_nodes=$(( num_nodes ))
expected_before=$(echo "scale=4; $sum_nodes/$num_nodes" | bc)

largest_container=""
largest_host=""
largest_number=-1

for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    if [[ -z "$containers" ]]; then
        continue
    fi
    for c in $containers; do
        num="${c##*_}"  # extract number after last underscore
        if [[ "$num" =~ ^[0-9]+$ && "$num" -gt "$largest_number" ]]; then
            largest_number="$num"
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

val="${largest_container##*_}"
curr_num_nodes=$((curr_num_nodes - 1))
sum_nodes=$((sum_nodes - val))
expected=$(echo "scale=4; $sum_nodes/$curr_num_nodes" | bc)

# Output JSON in new schema
jq -n \
    --arg t "$ts_ns" \
    --argjson b "$expected_before" \
    --argjson e "$expected" \
    --arg l "$largest_container" \
    '{expected_before: $b, events: [ {timestamp_ns: ($t|tonumber), expected: $e,  killed: [$l]} ]}'
