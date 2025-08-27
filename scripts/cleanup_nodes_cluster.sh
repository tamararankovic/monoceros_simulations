#!/usr/bin/env bash
set -euo pipefail

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

# Step 1: Get all unique hostnames from the network
HOSTNAMES=$(oar-p2p net show | awk '{print $1}' | sort -u)

echo "Hosts to clean: $HOSTNAMES"

# Step 2: Remove all containers on each host
for host in $HOSTNAMES; do
    echo "Cleaning containers on $host..."
    
    # List all container IDs and remove them
    ssh "$host" "docker ps -aq | xargs -r docker rm -f"
done

# Step 3: Bring down the P2P network
echo "Bringing down the network..."
oar-p2p net down

echo "All containers removed and network shut down."
