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

# declare -A initial_mem   # container → initial value
# declare -A container_host # container → host
# declare -A container_ip   # container → IP
# declare -A container_mem  # container → current mem value
# events=()

# for host in "${hosts[@]}"; do
#     output=$(ssh "$host" bash <<'REMOTE'
# for c in $(docker ps --format "{{.Names}}"); do
#     listen_var=$(docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" "$c" | grep "LISTEN_" | head -n1)
#     if [[ -n "$listen_var" ]]; then
#         ip_port=${listen_var#*=}   # remove LISTEN_XXX=
#         ip=${ip_port%%:*}          # keep only IP before colon
#         echo "$c $ip"
#     fi
# done
# REMOTE
# )

#     while IFS= read -r line; do
#         cname=$(cut -d' ' -f1 <<<"$line")
#         cip=$(cut -d' ' -f2 <<<"$line")

#         initial_mem["$cname"]=$(awk -F'_' '{print $NF}' <<<"$cname")
#         container_host["$cname"]="$host"
#         container_ip["$cname"]="$cip"
#     done <<<"$output"
# done

# # set -x

# # echo $initial_mem

# # Step 2: compute expected_before
# sum_init=0
# for v in "${initial_mem[@]}"; do
#     sum_init=$((sum_init + v))
# done
# expected_before=$(echo "scale=4; $sum_init / $num_nodes" | bc)

# # Step 3: assign unique random values
# shuffled_vals=($(seq 1 "$num_nodes" | shuf))
# val_idx=0

# # echo "prep for sending cmds"

# for cname in "${!container_host[@]}"; do
#     host=${container_host[$cname]}
#     ip=${container_ip[$cname]}
#     mem_value=${shuffled_vals[$val_idx]}
#     val_idx=$((val_idx + 1))

#     output=$(ssh "$host" bash <<EOF
# curl -s -X POST -H 'Content-Type: text/plain' --data-binary @- "http://$ip:9200/metrics" <<METRICS
# # HELP app_memory_usage_bytes Current memory usage in bytes
# # TYPE app_memory_usage_bytes gauge
# app_memory_usage_bytes $mem_value

# $METRICS_TEMPLATE
# METRICS

# # Print container name and timestamp for event tracking
# echo "\$(date +%s%N)"
# EOF
# )

#     # echo $output

#     container_mem["$cname"]=$mem_value
#     # Compute expected using current mem + initial values for missing
#     total=0
#     for v in "${container_mem[@]}"; do
#         total=$((total + v))
#     done
#     missing=$((num_nodes - ${#container_mem[@]}))
#     if (( missing > 0 )); then
#         for c in "${!initial_mem[@]}"; do
#             if [[ -z "${container_mem[$c]:-}" ]]; then
#                 total=$((total + initial_mem[$c]))
#                 ((missing--))
#                 ((missing == 0)) && break
#             fi
#         done
#     fi

#     expected=$(echo "scale=4; $total / $num_nodes" | bc)
#     events+=("{\"timestamp_ns\": $output, \"expected\": $expected}")
#     # echo $events
# done

# # Step 5: output JSON
# printf '{ "expected_before": %f, "events": [%s] }\n' \
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

declare -A container_mem  # container → value (number from name)
events=()

for host in "${hosts[@]}"; do
    # echo "Processing host: $host"
    containers=$(ssh "$host" "docker ps --format '{{.Names}}'")
    while read -r c; do
        [[ -z "$c" ]] && continue
        # Extract number after last underscore
        num="${c##*_}"
        container_mem["$c"]="$num"
    done <<< "$containers"
done

sum_init=0
count=0
for v in "${container_mem[@]}"; do
    sum_init=$((sum_init + v))
    count=$((count + 1))
done

if ((count > 0)); then
    expected_before=$(echo "scale=4; $sum_init / $count" | bc)
    # expected_before=$(awk -v s="$sum_init" -v c="$count" 'BEGIN { printf "%.4f", s/c }')
else
    expected_before=0
fi

for host in "${hosts[@]}"; do
    output=$(ssh "$host" bash <<REMOTE
# single inspect for all containers
docker inspect \$(docker ps -q) \
  --format '{{range .Config.Env}}{{$.Name}} {{.}}{{"\n"}}{{end}}' |
  sed 's:^/::' |
while read -r name env; do
    if [[ \$env == *LISTEN_* ]]; then
        ip=\${env#*=}
        ip=\${ip%%:*}      # strip port
        num=\${name##*_}   # suffix from name
        mem_value=\$((num * 2))

        curl -s -X POST -H 'Content-Type: text/plain' \
             --data-binary @- "http://\$ip:9200/metrics" <<METRICS
# HELP app_memory_usage_bytes Current memory usage in bytes
# TYPE app_memory_usage_bytes gauge
app_memory_usage_bytes \$mem_value

$METRICS_TEMPLATE
METRICS

        echo "\$name \$mem_value \$(date +%s%N)"
    fi
done
REMOTE
)

    while read -r line; do
        [[ -z "$line" ]] && continue
        cname=$(awk '{print $1}' <<< "$line")
        mem_value=$(awk '{print $2}' <<< "$line")
        timestamp_ns=$(awk '{print $3}' <<< "$line")

        container_mem["$cname"]="$mem_value"

        # compute current average as float
        sum_cur=0
        for v in "${container_mem[@]}"; do
            sum_cur=$(echo "scale=4; $sum_cur + $v" | bc)
        done
        avg_cur=$(echo "scale=4; $sum_cur / ${#container_mem[@]}" | bc)

        # add event JSON
        events+=("{\"timestamp_ns\": $timestamp_ns, \"expected\": $avg_cur,  \"killed\": []}")
    done <<< "$output"

done

# # Output final JSON
jq -n --argjson expected_before "$expected_before" \
      --argjson events "$(printf '%s\n' "${events[@]}" | jq -s '.')" \
      '{expected_before: $expected_before, events: $events}'