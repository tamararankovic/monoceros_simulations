#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <num_nodes>"
    exit 1
fi

num_nodes="$1"

ts_ns=$(gdate +%s%N)

jq -n \
    --arg t "$ts_ns" \
    --argjson n "$num_nodes" \
    '{timestamp_ns: ($t|tonumber),
      expected_before: ($n * 512),
      expected_after: ($n * 512)}'