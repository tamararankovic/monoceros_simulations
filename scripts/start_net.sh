#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <num_nodes> <num_regions> <intraregional_latency> <interregional_latency>"
  exit 1
fi

NODES="$1"
REGIONS="$2"
INTRA_LATENCY="$3"
INTER_LATENCY="$4"

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

add_ssh_hosts_for_job() {
    local job_id="$1"
    local frontend_host="$2"
    local ssh_config="$HOME/.ssh/config"
    local user_name="tamara"
    local proxy="tamara@nova_cluster"

    if [ -z "$job_id" ]; then
        echo "Error: job ID not provided"
        return 1
    fi

    if [ -z "$frontend_host" ]; then
        echo "Error: FRONTEND_HOSTNAME is not set"
        return 1
    fi

    # Get assigned_hostnames remotely
    local host_line
    host_line=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$frontend_host" \
        "oarstat -f nodename -j $job_id" 2>/dev/null | grep 'assigned_hostnames' || true)

    if [ -z "$host_line" ]; then
        echo "No assigned hostnames found for job $job_id"
        return 0
    fi

    local hostnames
    hostnames=$(echo "$host_line" | awk -F'= ' '{print $2}' | tr '+' '\n')

    while read -r host; do
        [ -z "$host" ] && continue
        if ! grep -q "Host $host" "$ssh_config"; then
            echo -e "\nHost $host\n    User $user_name\n    ProxyJump $proxy" >> "$ssh_config"
            echo "Added $host to $ssh_config"
        else
            echo "$host already exists in $ssh_config"
        fi
    done <<< "$hostnames"
}

# Make sure $OAR_JOB_ID is set
if [ -z "${OAR_JOB_ID:-}" ]; then
    echo "Error: OAR_JOB_ID is not set"
    exit 1
fi

# Add SSH hosts for the job
add_ssh_hosts_for_job "$OAR_JOB_ID" "$FRONTEND_HOSTNAME"

# Generate latency
cd ../latency
rm -f latency.txt
go run main.go "$NODES" "$INTRA_LATENCY" "$REGIONS" "$INTER_LATENCY"
oar-p2p net up --addresses "$NODES" --latency-matrix latency.txt