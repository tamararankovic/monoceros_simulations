#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
num_iterations=5
shift
hosts=("$@")

declare -A container_mem
events=()

# --- Gather container names from all hosts ---
for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    while read -r c; do
        [[ -z "$c" ]] && continue
        num="${c##*_}"
        container_mem["$c"]="$num"
    done <<< "$containers"
done

# --- Compute initial average ---
sum_init=0
count=0
for v in "${container_mem[@]}"; do
    sum_init=$((sum_init + v))
    count=$((count + 1))
done
expected_before=$( ((count > 0)) && echo "scale=4; $sum_init / $count" | bc || echo 0 )

# --- Iterate N times ---
for ((i=1; i<=num_iterations; i++)); do
    # echo ">>> Iteration $i / $num_iterations"

    for host in "${hosts[@]}"; do
        output=$(ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail

# Select containers whose name ends with '0' (10%)
selected=($(docker ps --format '{{.Names}}' | grep '0$'))

for name in "${selected[@]}"; do
    ip_env=$(docker inspect "$name" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep LISTEN_ | head -n1)
    if [[ -z "$ip_env" ]]; then
        continue
    fi
    ip=${ip_env#*=}
    ip=${ip%%:*}

    # Get previous mem value if exists
    prev_val_file="$HOME/$name.mem_prev"
    if [[ -f "$prev_val_file" ]]; then
        prev_val=$(cat "$prev_val_file")
    else
        num=${name##*_}
        prev_val=$num
    fi

    mem_value=$(awk "BEGIN {printf \"%.2f\", $prev_val * 1.05}")

    # Save new value for next iteration
    echo "$mem_value" > "$prev_val_file"

    curl -s -X POST -H 'Content-Type: text/plain' \
         --data-binary @- "http://$ip:9200/metrics" <<METRICS
# HELP app_memory_usage_bytes Current memory usage in bytes
# TYPE app_memory_usage_bytes gauge
app_memory_usage_bytes $mem_value

METRICS

    echo "$name $mem_value $(date +%s%N)"
done
REMOTE
)

        while read -r line; do
            [[ -z "$line" ]] && continue
            cname=$(awk '{print $1}' <<< "$line")
            mem_value=$(awk '{print $2}' <<< "$line")
            timestamp_ns=$(awk '{print $3}' <<< "$line")

            container_mem["$cname"]="$mem_value"

            sum_cur=0
            for v in "${container_mem[@]}"; do
                sum_cur=$(awk "BEGIN {print $sum_cur + $v}")
            done
            avg_cur=$(awk "BEGIN {print $sum_cur / ${#container_mem[@]}}")

            events+=("{\"iteration\": $i, \"timestamp_ns\": $timestamp_ns, \"expected\": $avg_cur, \"killed\": []}")
        done <<< "$output"
    done

    if (( i < num_iterations )); then
        # echo "Sleeping 10s before next iteration..."
        sleep 10
    fi
done

# --- Cleanup .mem_prev files on all hosts ---
for host in "${hosts[@]}"; do
    ssh "$host" "rm -f \$HOME/*.mem_prev" || echo "Warning: failed to remove .mem_prev files on $host"
done

# --- Output JSON ---
jq -n --argjson expected_before "$expected_before" \
      --argjson events "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
      '{expected_before: $expected_before, events: $events}'
