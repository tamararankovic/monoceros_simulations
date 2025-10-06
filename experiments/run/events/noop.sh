#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <num_nodes>"
    exit 1
fi

num_nodes="$1"

ts_ns=$(gdate +%s%N)

sum_nodes=$(( num_nodes * (num_nodes + 1) / 2 ))
expected_before=$(echo "scale=4; $sum_nodes/$num_nodes" | bc)

jq -n \
    --arg t "$ts_ns" \
    --argjson e "$expected_before" \
    '{expected_before: $e, events: [ {timestamp_ns: ($t|tonumber), expected: $e, killed: [] } ]}'