#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <num_nodes>"
    exit 1
fi

num_nodes="$1"

ts_ns=$(gdate +%s%N)

# Output JSON in new schema
# jq -n \
#     --arg t "$ts_ns" \
#    --argjson n "$num_nodes" \
#     '{expected_before: (($n + 1) / 2), events: [ {timestamp_ns: ($t|tonumber), expected: (($n + 1) / 2)} ]}'

jq -n \
    --arg t "$ts_ns" \
    '{expected_before: 512, events: [ {timestamp_ns: ($t|tonumber), expected: 512 } ]}'