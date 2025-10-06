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

# Group containers by host (space-separated)
declare -A host_containers
for hc in "${containers_to_kill[@]}"; do
    host="${hc%%:*}"
    c="${hc##*:}"
    # append with a space separator
    host_containers["$host"]+="$c "
done

# Kill containers host by host (one ssh per host)
events=()
sum_nodes=$(( num_nodes * (num_nodes + 1) / 2 ))
curr_num_nodes=$(( num_nodes ))
expected_before=$(echo "scale=4; $sum_nodes/$num_nodes" | bc)

for host in "${!host_containers[@]}"; do
    # read container list into an array
    read -r -a container_list <<< "${host_containers[$host]}"
    if (( ${#container_list[@]} == 0 )); then
        continue
    fi

    # run a single ssh that receives the container names as args and prints timestamps
    output=$(ssh "$host" bash -s -- "${container_list[@]}" <<'REMOTE'
for c in "$@"; do
    docker kill "$c" >/dev/null || true
    ts_ns=$(date +%s%N)
    echo "$ts_ns $c"
done
REMOTE
)

    # collect timestamp + container name from the remote host
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ts_ns="${line%% *}"        # first field = timestamp
        c_name="${line#* }"        # rest = container name
        val="${c_name##*_}"
        curr_num_nodes=$((curr_num_nodes - 1))
        sum_nodes=$((sum_nodes - val))
        expected=$(echo "scale=4; $sum_nodes/$curr_num_nodes" | bc)
        events+=("{\"timestamp_ns\": $ts_ns, \"expected\": $expected, \"killed\": [\"$c_name\"]}")
    done <<< "$output"
done

# Output JSON
jq -n \
    --argjson b "$expected_before" \
    --argjson ev "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
    '{expected_before: $b, events: $ev}'
