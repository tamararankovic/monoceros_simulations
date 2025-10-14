#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
num_iterations=5
shift
hosts=("$@")

MEM_FILE="container_mem_values.txt"  # file to store persistent memory values

# Base metrics (constant part)
METRICS_TEMPLATE='
# HELP app_request_processing_time_seconds Average request processing time
# TYPE app_request_processing_time_seconds gauge
app_request_processing_time_seconds 0.256

# HELP app_cpu_load_ratio CPU load (0-1)
# TYPE app_cpu_load_ratio gauge
app_cpu_load_ratio 0.13

# HELP app_active_sessions Current active user sessions
# TYPE app_active_sessions gauge
app_active_sessions 42

# HELP app_queue_depth_pending_jobs Jobs waiting in queue
# TYPE app_queue_depth_pending_jobs gauge
app_queue_depth_pending_jobs 7

# HELP app_cache_hit_ratio Cache hit ratio
# TYPE app_cache_hit_ratio gauge
app_cache_hit_ratio 0.82

# HELP app_current_goroutines Goroutine count
# TYPE app_current_goroutines gauge
app_current_goroutines 33

# HELP app_last_backup_timestamp_seconds Unix timestamp of last successful backup
# TYPE app_last_backup_timestamp_seconds gauge
app_last_backup_timestamp_seconds 1.700000e+09

# HELP app_http_requests_total Total HTTP requests processed
# TYPE app_http_requests_total counter
app_http_requests_total 12890

# HELP app_errors_total Total errors encountered
# TYPE app_errors_total counter
app_errors_total 17
'

declare -A container_mem
events=()

# --- Load previous mem values if file exists ---
if [[ -f "$MEM_FILE" ]]; then
    while read -r line; do
        [[ -z "$line" ]] && continue
        cname=$(awk '{print $1}' <<< "$line")
        val=$(awk '{print $2}' <<< "$line")
        container_mem["$cname"]="$val"
    done < "$MEM_FILE"
fi

# --- Gather all containers ---
for host in "${hosts[@]}"; do
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    while read -r c; do
        [[ -z "$c" ]] && continue
        if [[ -z "${container_mem[$c]+set}" ]]; then
            # if not yet stored, initialize with container suffix
            num="${c##*_}"
            container_mem["$c"]="$num"
        fi
    done <<< "$containers"
done

# --- Compute initial expected average ---
sum_init=0
count=0
for v in "${container_mem[@]}"; do
    sum_init=$(awk "BEGIN {print $sum_init + $v}")
    count=$((count + 1))
done
expected_before=$(awk "BEGIN {print $sum_init / $count}")

# --- Iterate N times ---
for ((i=1; i<=num_iterations; i++)); do
    echo ">>> Iteration $i / $num_iterations"

    for host in "${hosts[@]}"; do
        output=$(ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail

containers=($(docker ps --format '{{.Names}}'))
total=${#containers[@]}
if (( total == 0 )); then
    exit 0
fi

# Select every 10th container
selected=()
for ((i=0; i<total; i+=10)); do
    selected+=("${containers[$i]}")
done

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
        echo "Sleeping 10s before next iteration..."
        sleep 10
    fi
done

# --- Output JSON ---
jq -n --argjson expected_before "$expected_before" \
      --argjson events "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
      '{expected_before: $expected_before, events: $events}'
