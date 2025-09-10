#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
shift
hosts=("$@")

# Find the container with the largest name across all hosts
largest_container=""
largest_host=""
all_containers=()

for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    if [[ -z "$containers" ]]; then
        continue
    fi
    for c in $containers; do
        all_containers+=("$host:$c")
        if [[ -z "$largest_container" || "$c" > "$largest_container" ]]; then
            largest_container="$c"
            largest_host="$host"
        fi
    done
done

if [[ ${#all_containers[@]} -eq 0 ]]; then
    echo '{"expected_before": 0, "events": []}'
    exit 0
fi

# Filter out the largest container
killable_containers=()
for hc in "${all_containers[@]}"; do
    host="${hc%%:*}"
    c="${hc##*:}"
    if [[ "$c" != "$largest_container" ]]; then
        killable_containers+=("$hc")
    fi
done

# Compute number to kill (50%)
num_to_kill=$(( (${#all_containers[@]} + 1) / 2 ))  # round up
if (( num_to_kill > ${#killable_containers[@]} )); then
    num_to_kill=${#killable_containers[@]}
fi

# Pick first N containers to kill
containers_to_kill=("${killable_containers[@]:0:num_to_kill}")

# Kill containers and record events
events=()
for hc in "${containers_to_kill[@]}"; do
    host="${hc%%:*}"
    expected=512
    ts_ns=$(ssh "$host" bash -c "docker stop \"$c\" >/dev/null; date +%s%N")
    events+=("{\"timestamp_ns\": $ts_ns, \"expected\": $expected}")
done

# Compute expected memory (assuming each container has 512 units)
expected_before=$(( 512 ))

# Output JSON
jq -n \
    --argjson b "$expected_before" \
    --argjson ev "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
    '{expected_before: $b, events: $ev}'
