#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
    exit 1
fi

num_nodes="$1"
shift
hosts=("$@")

# Base metrics template (all except app_memory_usage_bytes)
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

declare -A container_mem  # Tracks memory per container
events=()

for i in $(seq 1 6); do
    # Determine new memory value
    if (( i <= 3 )); then
        mem_change=$((512 * i))
    else
        mem_change=$((512 * (6 - i)))
    fi
    mem_value=$((512 + mem_change))  # base 512

    for host in "${hosts[@]}"; do
        # Run SSH and send metrics to each container
        output=$(ssh "$host" bash <<EOF
for c in \$(docker ps --format '{{.Names}}'); do
    env_ip=\$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "\$c" | grep '^HTTP_' | head -n1 || true)
    if [[ -n "\$env_ip" ]]; then
        ip_port=\${env_ip#*=}
        ip=\${ip_port%%:*}

        curl -s -X POST -H 'Content-Type: text/plain' --data-binary @- "http://\$ip:9200/metrics" <<METRICS
# HELP app_memory_usage_bytes Current memory usage in bytes
# TYPE app_memory_usage_bytes gauge
app_memory_usage_bytes $mem_value

$METRICS_TEMPLATE
METRICS

        # Print container name and timestamp for event tracking
        echo "\$c \$(date +%s%N)"
    fi
done
EOF
)

        # Process each container’s output as an event
        while IFS= read -r line; do
            cname=$(cut -d' ' -f1 <<<"$line")
            ts_ns=$(cut -d' ' -f2 <<<"$line")

            # Update container memory
            container_mem["$cname"]=$mem_value

            # Compute expected sum across all containers (default 512 if not seen)
            expected=0
            for val in "${container_mem[@]}"; do
                expected=$((expected + val))
            done
            missing=$((num_nodes - ${#container_mem[@]}))
            if (( missing > 0 )); then
                expected=$((expected + 512 * missing))
            fi

            events+=("{\"timestamp_ns\": $ts_ns, \"expected\": $expected}")
        done <<<"$output"
    done

    sleep 5
done

expected_before=$((num_nodes * 512))

# Output final JSON
printf '{ "expected_before": %d, "events": [%s] }\n' \
    "$expected_before" "$(IFS=,; echo "${events[*]}")"
