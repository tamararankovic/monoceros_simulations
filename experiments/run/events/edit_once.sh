#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
shift
hosts=("$@")

# --- Metrics template ---
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

# --- For each host, send metrics for 10% of containers ---
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
    num=${name##*_}
    mem_value=$((num / 2))

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
            sum_cur=$(echo "scale=4; $sum_cur + $v" | bc)
        done
        avg_cur=$(echo "scale=4; $sum_cur / ${#container_mem[@]}" | bc)

        events+=("{\"timestamp_ns\": $timestamp_ns, \"expected\": $avg_cur, \"killed\": []}")
    done <<< "$output"
done

jq -n --argjson expected_before "$expected_before" \
      --argjson events "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
      '{expected_before: $expected_before, events: $events}'
