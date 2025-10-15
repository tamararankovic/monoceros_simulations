#!/usr/bin/env bash
set -euo pipefail

prefixes=(mc fu dd rr ep)

PLAN_FILE="plan.csv"

for prefix in "${prefixes[@]}"; do
    echo "Writing plan.csv for prefix: $prefix"

    {
        echo "protocol,exp_name,nodes_count,regions_count,latency_local,latency_global,repeat,stabilization_wait,event_wait,event,end_wait"
        echo "${prefix},kill_50,100,1,50,200,2,60,20,kill_50,120"
    } > "$PLAN_FILE"

    echo "Running run.sh for prefix: $prefix..."
    bash run.sh

    echo "Completed run for prefix: $prefix"
done

echo "All runs done."
