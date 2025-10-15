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

# Collect all containers with their numbers and hosts
declare -a container_list  # format: "num host container_name"

for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    if [[ -z "$containers" ]]; then
        continue
    fi
    for c in $containers; do
        num="${c##*_}"  # extract number after last underscore
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            container_list+=("$num $host $c")
        fi
    done
done

if [[ ${#container_list[@]} -eq 0 ]]; then
    echo '{"expected_before": 0, "events": []}'
    exit 0
fi

# Sort containers by number descending and pick top 3
IFS=$'\n' sorted=($(sort -rn <<<"${container_list[*]}"))
top3=("${sorted[@]:0:3}")

killed_containers=()
for entry in "${top3[@]}"; do
    num=$(awk '{print $1}' <<<"$entry")
    host=$(awk '{print $2}' <<<"$entry")
    c=$(awk '{print $3}' <<<"$entry")
    
    # Stop container and get timestamp
    ts_ns=$(ssh "$host" bash -c "'
        docker stop \"$c\" >/dev/null
        date +%s%N
    '")
    
    killed_containers+=("$c")
    
    # Update sums for expected calculation
    curr_num_nodes=$((curr_num_nodes - 1))
    sum_nodes=$((sum_nodes - num))
done

expected=$(echo "scale=4; $sum_nodes/$curr_num_nodes" | bc)

# Output JSON in new schema
jq -n \
    --arg t "$ts_ns" \
    --argjson b "$expected_before" \
    --argjson e "$expected" \
    --argjson killed "$(jq -R -s -c 'split("\n")[:-1]' <<<"${killed_containers[*]}")" \
    '{expected_before: $b, events: [ {timestamp_ns: ($t|tonumber), expected: $e,  killed: $killed} ]}'
