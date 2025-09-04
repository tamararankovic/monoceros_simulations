#!/usr/bin/env bash
set -euo pipefail

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

# Step 1: Bring down the P2P network
echo "Bringing down the network..."
oar-p2p net down

echo "All containers removed and network shut down."
