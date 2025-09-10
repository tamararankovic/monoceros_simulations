# #!/usr/bin/env bash
# set -euo pipefail

# if [[ $# -lt 2 ]]; then
#     echo "Usage: $0 <num_nodes> <host1> [host2 ...]"
#     exit 1
# fi

# num_nodes="$1"
# shift
# hosts=("$@")

# # Base metrics template (all except app_memory_usage_bytes)
# METRICS_TEMPLATE='
# # HELP app_request_processing_time_seconds Average request processing time
# # TYPE app_request_processing_time_seconds gauge
# app_request_processing_time_seconds 0.256

# # HELP app_cpu_load_ratio CPU load (0-1)
# # TYPE app_cpu_load_ratio gauge
# app_cpu_load_ratio 0.13

# # HELP app_active_sessions Current active user sessions
# # TYPE app_active_sessions gauge
# app_active_sessions 42

# # HELP app_queue_depth_pending_jobs Jobs waiting in queue
# # TYPE app_queue_depth_pending_jobs gauge
# app_queue_depth_pending_jobs 7

# # HELP app_cache_hit_ratio Cache hit ratio
# # TYPE app_cache_hit_ratio gauge
# app_cache_hit_ratio 0.82

# # HELP app_current_goroutines Goroutine count
# # TYPE app_current_goroutines gauge
# app_current_goroutines 33

# # HELP app_last_backup_timestamp_seconds Unix timestamp of last successful backup
# # TYPE app_last_backup_timestamp_seconds gauge
# app_last_backup_timestamp_seconds 1.700000e+09

# # HELP app_http_requests_total Total HTTP requests processed
# # TYPE app_http_requests_total counter
# app_http_requests_total 12890

# # HELP app_errors_total Total errors encountered
# # TYPE app_errors_total counter
# app_errors_total 17
# '

# declare -A container_mem  # Tracks memory per container
# events=()

# for i in $(seq 1 6); do
#     # Determine new memory value
#     if (( i <= 3 )); then
#         mem_change=$((512 * i))
#     else
#         mem_change=$((512 * (6 - i)))
#     fi
#     mem_value=$((512 + mem_change))  # base 512

#     for host in "${hosts[@]}"; do
#         # Run SSH and send metrics to each container
#         output=$(ssh "$host" bash <<EOF
# for c in \$(docker ps --format '{{.Names}}'); do
#     env_ip=\$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "\$c" | grep 'LISTEN_' | head -n1 || true)
#     if [[ -n "\$env_ip" ]]; then
#         ip_port=\${env_ip#*=}
#         ip=\${ip_port%%:*}

#         curl -s -X POST -H 'Content-Type: text/plain' --data-binary @- "http://\$ip:9200/metrics" <<METRICS
# # HELP app_memory_usage_bytes Current memory usage in bytes
# # TYPE app_memory_usage_bytes gauge
# app_memory_usage_bytes $mem_value

# $METRICS_TEMPLATE
# METRICS

#         # Print container name and timestamp for event tracking
#         echo "\$c \$(date +%s%N)"
#     fi
# done
# EOF
# )

#         # Process each container’s output as an event
#         while IFS= read -r line; do
#             cname=$(cut -d' ' -f1 <<<"$line")
#             ts_ns=$(cut -d' ' -f2 <<<"$line")

#             # Update container memory
#             container_mem["$cname"]=$mem_value

#              # Compute expected average across all containers
#             total=0
#             for val in "${container_mem[@]}"; do
#                 total=$((total + val))
#             done
#             missing=$((num_nodes - ${#container_mem[@]}))
#             if (( missing > 0 )); then
#                 total=$((total + 512 * missing))  # missing containers start at 512
#             fi
#             expected=$((total / num_nodes))   # use average, not sum

#             events+=("{\"timestamp_ns\": $ts_ns, \"expected\": $expected}")

#             # # Compute expected sum across all containers (default 512 if not seen)
#             # expected=0
#             # for val in "${container_mem[@]}"; do
#             #     expected=$((expected + val))
#             # done
#             # missing=$((num_nodes - ${#container_mem[@]}))
#             # if (( missing > 0 )); then
#             #     expected=$((expected + 512 * missing))
#             # fi

#             # events+=("{\"timestamp_ns\": $ts_ns, \"expected\": $expected}")
#         done <<<"$output"
#     done

#     sleep 5
# done

# # expected_before=$((num_nodes * 512))
# expected_before=$(( 512 ))

# # Output final JSON
# printf '{ "expected_before": %d, "events": [%s] }\n' \
#     "$expected_before" "$(IFS=,; echo "${events[*]}")"


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

declare -A container_mem   # Tracks memory per container
declare -A initial_mem     # Initial memory from container names
events=()

# Generate a shuffled list of unique random values [1..num_nodes]
shuffled_vals=($(seq 1 "$num_nodes" | shuf))
val_idx=0

for host in "${hosts[@]}"; do
    output=$(ssh "$host" bash <<EOF
for c in \$(docker ps --format '{{.Names}}'); do
    env_ip=\$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "\$c" | grep 'LISTEN_' | head -n1 || true)
    if [[ -n "\$env_ip" ]]; then
        ip_port=\${env_ip#*=}
        ip=\${ip_port%%:*}

        echo "\$c"
    fi
done
EOF
)

    while IFS= read -r cname; do
        [[ -z "\$cname" ]] && continue

        # Extract initial value from name (last underscore + number)
        init_val=\$(awk -F'_' '{print \$NF}' <<<"\$cname")
        initial_mem["$cname"]=\$init_val

        # Assign unique random value
        mem_value=\${shuffled_vals[\$val_idx]}
        ((val_idx++))

        ts_ns=\$(date +%s%N)

        curl -s -X POST -H 'Content-Type: text/plain' --data-binary @- "http://\$ip:9200/metrics" <<METRICS
# HELP app_memory_usage_bytes Current memory usage in bytes
# TYPE app_memory_usage_bytes gauge
app_memory_usage_bytes \$mem_value

$METRICS_TEMPLATE
METRICS

        echo "\$cname \$mem_value \$ts_ns"
    done <<<"\$output"
done

# Process results
while IFS= read -r line; do
    cname=\$(cut -d' ' -f1 <<<"\$line")
    mem_value=\$(cut -d' ' -f2 <<<"\$line")
    ts_ns=\$(cut -d' ' -f3 <<<"\$line")

    container_mem["\$cname"]=\$mem_value

    # Compute expected average across all containers
    total=0
    for c in "\${!container_mem[@]}"; do
        total=\$((total + container_mem[\$c]))
    done

    missing=\$((num_nodes - \${#container_mem[@]}))
    if (( missing > 0 )); then
        # Use per-container initial values for missing ones
        for c in "\${!initial_mem[@]}"; do
            if [[ -z "\${container_mem[\$c]:-}" ]]; then
                total=\$((total + initial_mem[\$c]))
                ((missing--))
                ((missing == 0)) && break
            fi
        done
    fi

    expected=\$((total / num_nodes))
    events+=("{\"timestamp_ns\": \$ts_ns, \"expected\": \$expected}")
done <<<"$(for host in "${hosts[@]}"; do echo "$output"; done)"

# Expected before = average of initial values
sum_init=0
for v in "\${initial_mem[@]}"; do
    sum_init=\$((sum_init + v))
done
expected_before=\$((sum_init / num_nodes))

# Output final JSON
printf '{ "expected_before": %d, "events": [%s] }\n' \
    "\$expected_before" "\$(IFS=,; echo "\${events[*]}")"
