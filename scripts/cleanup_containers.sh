#!/usr/bin/env bash
set -euo pipefail

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

# Step 1: Get all unique hostnames from the network
HOSTNAMES=$(oar-p2p net show | awk '{print $1}' | sort -u)

echo "Hosts to clean: $HOSTNAMES"

# Step 2: Remove all containers and clear packet loss rules on each host
for host in $HOSTNAMES; do
    echo "Cleaning containers and packet loss rules on $host..."

    # List all containers
    CONTAINERS=$(ssh "$host" "docker ps -q")

    # Remove containers
    if [[ -n "$CONTAINERS" ]]; then
        ssh "$host" "docker rm -f $CONTAINERS"
    fi

    # If there are no containers, skip interface detection
    if [[ -z "$CONTAINERS" ]]; then
        continue
    fi

    # Pick the first container to determine interface
    FIRST_CONTAINER=$(echo "$CONTAINERS" | head -n1)

    # Get container's IP from HTTP_SERVER_ADDR env variable
    CONTAINER_IP=$(ssh "$host" "docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $FIRST_CONTAINER | grep '^HTTP_SERVER_ADDR=' | cut -d'=' -f2 | cut -d':' -f1")

    if [[ -n "$CONTAINER_IP" ]]; then
        # Determine host interface used to reach container IP
        INTERFACE=$(ssh "$host" "ip route get $CONTAINER_IP | awk '{for(i=1;i<=NF;i++){if(\$i==\"dev\") print \$(i+1)}}'")
        if [[ -n "$INTERFACE" ]]; then
            echo "Deleting all qdiscs on interface $INTERFACE"
            ssh "$host" "sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true"
        else
            echo "Could not detect interface for $host/$FIRST_CONTAINER"
        fi
    else
        echo "Could not find HTTP_SERVER_ADDR for $host/$FIRST_CONTAINER"
    fi
done
