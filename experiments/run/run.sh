#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE="plan.csv"
BASE_EXP_DIR="/home/tamara/experiments/results"
MAX_RETRIES=2

# Get the first remote hostname
HOSTS_LINE=$(ssh nova_cluster "oarstat -fj $OAR_JOB_ID" | grep 'assigned_hostnames')
HOSTS_STR=$(echo "$HOSTS_LINE" | awk -F'=' '{gsub(/ /,"",$2); print $2}')
IFS='+' read -r -a HOSTS_ARRAY <<< "$HOSTS_STR"
FIRST_HOST=${HOSTS_ARRAY[0]}

while IFS=',' read -r protocol exp_name nodes_count regions_count latency_local latency_global repeat stabilization_wait event_wait event end_wait || [[ -n $exp_name ]]
do
    echo "======================================"
    echo "Running experiment: $exp_name"
    # Set up network
    echo "      Setting up network with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
    pushd ../../scripts > /dev/null
    ./start_net.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global"
    popd > /dev/null

    FULL_EXP_NAME="${protocol}_${exp_name}_${nodes_count}_${regions_count}"
    EXP_DIR_BASE="$BASE_EXP_DIR/$FULL_EXP_NAME"

    for ((i=1; i<=repeat; i++)); do
        echo "  Repeat $i/$repeat"

        retry_count=0
        while true; do
            retry_count=$((retry_count+1))
            echo $retry_count
            if (( retry_count > MAX_RETRIES )); then
                echo "      Maximum retries ($MAX_RETRIES) exceeded for this repetition. Exiting."
                # Clean up network
                echo "      Cleaning up network"
                pushd ../../scripts > /dev/null
                ./cleanup_net.sh
                popd > /dev/null
                exit 1
            fi
            echo "    Attempt $retry_count for repetition $i"

            # Create directory and clean logs on remote host
            ssh "$FIRST_HOST" "
                rm -rf /home/tamara/monoceros_simulations/scripts/log/*
                mkdir -p $EXP_DIR_BASE/exp_$i
            "

            # Go to scripts directory locally
            pushd ../../scripts > /dev/null

            # Start containers depending on protocol
            if [[ "$protocol" == "mc" ]]; then
                echo "      Starting cluster (monoceros) with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
                ./start_containers.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global" "$FULL_EXP_NAME/exp_$i"
            elif [[ "$protocol" == "fu" ]]; then
                echo "      Starting cluster (flow updating) with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
                ./start_fu.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global" "$FULL_EXP_NAME/exp_$i"
            elif [[ "$protocol" == "dd" ]]; then
                echo "      Starting cluster (digest diffusion) with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
                ./start_dd.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global" "$FULL_EXP_NAME/exp_$i"
            elif [[ "$protocol" == "rr" ]]; then
                echo "      Starting cluster (randomized reports) with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
                ./start_rr.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global" "$FULL_EXP_NAME/exp_$i"
            elif [[ "$protocol" == "ep" ]]; then
                echo "      Starting cluster (extrema propagation) with nodes=$nodes_count, regions=$regions_count, latencies=$latency_local/$latency_global"
                ./start_ep.sh "$nodes_count" "$regions_count" "$latency_local" "$latency_global" "$FULL_EXP_NAME/exp_$i"
            else
                echo "      Unknown protocol: $protocol"
                exit 1
            fi

            # Wait for stabilization
            echo "      Waiting for stabilization: $stabilization_wait seconds"
            sleep "$stabilization_wait"

            # Timestamp after stabilization (local)
            ts_stabilization=$(gdate +%s%N)

            # --- Check weakly connected components ---
            echo "      Checking network connectivity..."
            ./regional_net.sh
            source venv/bin/activate
            wc_output=$(python3 regional_net.py)
            echo "        $wc_output"
            num_components=$(echo "$wc_output" | awk -F': ' '{print $NF}')
            popd > /dev/null

            if [[ "$num_components" -ne "$regions_count" ]]; then
                echo "        Weakly connected components ($num_components) != regions_count ($regions_count), retrying entire repetition..."
                # Stop cluster before retrying
                pushd ../../scripts > /dev/null
                ./cleanup_containers.sh
                popd > /dev/null
                continue  # retry the whole repetition
            fi

            echo "      Cluster stabilized correctly with $num_components components."
            break  # exit retry loop, proceed to event

        done  # end retry loop

        # Optional wait before event
        if [[ -n "$event_wait" && "$event_wait" != "0" ]]; then
            echo "    Waiting before event: $event_wait seconds"
            sleep "$event_wait"
        fi

        # Timestamp before event (local)
        ts_event_start=$(gdate +%s%N)

        # Run event script
        echo "    Running event: $event"
        event_json=$(bash "../../experiments/run/events/${event}.sh" "$nodes_count" "${HOSTS_ARRAY[@]}")

        # Timestamp after event (local)
        ts_event_end=$(gdate +%s%N)

        # Wait after event
        if [[ -n "$end_wait" && "$end_wait" != "0" ]]; then
            echo "    Waiting after event: $end_wait seconds"
            sleep "$end_wait"
        fi

        # Timestamp after event (local)
        ts_experiment_end=$(gdate +%s%N)

        # Cleanup containers
        pushd ../../scripts > /dev/null
        echo "    Cleaning up containers"
        ./cleanup_containers.sh
        popd > /dev/null

        # Write metadata to remote host
        plan_json=$(jq -n \
            --arg en "$exp_name" \
            --arg nc "$nodes_count" \
            --arg rc "$regions_count" \
            --arg ll "$latency_local" \
            --arg lg "$latency_global" \
            --arg rp "$repeat" \
            --arg sw "$stabilization_wait" \
            --arg ew "$event_wait" \
            --arg ev "$event" \
            --arg exw "$end_wait" \
            '{
                exp_name: $en,
                nodes_count: ($nc|tonumber),
                regions_count: ($rc|tonumber),
                latency_local: ($ll|tonumber),
                latency_global: ($lg|tonumber),
                repeat: ($rp|tonumber),
                stabilization_wait: ($sw|tonumber),
                event_wait: ($ew|tonumber),
                event: $ev,
                end_wait: ($exw|tonumber)
            }'
        )
        timestamps_json=$(jq -n \
            --arg st "$ts_stabilization" \
            --arg es "$ts_event_start" \
            --arg ee "$ts_event_end" \
            --arg ex "$ts_experiment_end" \
            '{
                stabilization_done_ns: ($st|tonumber),
                event_start_ns: ($es|tonumber),
                event_end_ns: ($ee|tonumber),
                experiment_end_ns: ($ex|tonumber)
            }'
        )
        metadata_json=$(jq -n \
            --argjson plan "$plan_json" \
            --argjson timestamps "$timestamps_json" \
            --argjson event_data "$event_json" \
            '{plan: $plan, timestamps: $timestamps, event_data: $event_data}')
        METADATA_FILE="$EXP_DIR_BASE/exp_$i/metadata.json"
        # Write metadata to remote host
        # ssh "$FIRST_HOST" "mkdir -p $(dirname "$METADATA_FILE")"  # ensure directory exists
        echo "$metadata_json" | ssh "$FIRST_HOST" "cat > '$METADATA_FILE'"
        # Move logs to experiment directory on remote host
        # ssh "$FIRST_HOST" "mv /home/tamara/monoceros_simulations/scripts/log/* $EXP_DIR_BASE/exp_$i/"

        echo "  Repeat $i done. Logs and timestamps saved on $FIRST_HOST:$EXP_DIR_BASE/exp_$i"

    done  # end repeat loop

    # Clean up network
    echo "      Cleaning up network"
    pushd ../../scripts > /dev/null
    ./cleanup_net.sh
    popd > /dev/null

done < <(tail -n +2 "$PLAN_FILE")