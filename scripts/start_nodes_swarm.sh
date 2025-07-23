#!/usr/bin/env bash
# start_nodes.sh — Starts N Docker Swarm services with region-based naming.
#
# USAGE:
#   ./start_nodes.sh <start_index> <number_of_nodes> <region> <gn_region> <port_offset>
#
# EXAMPLE:
#   ./start_nodes.sh 1 5 r1 r1 0

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <start_index> <number_of_nodes> <region> <gn_region> <port_offset>"
  exit 1
fi

INDEX="$1"
COUNT="$2"
REGION="$3"
GN_REGION="$4"
PORT_OFFSET="$5"
NETWORK="p2p_overlay"
IMAGE="monoceros-all"

# Ensure Swarm mode is active
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q 'active'; then
  echo "⚠️  Docker Swarm not initialized. Run 'docker swarm init' first."
  exit 1
fi

# Create overlay network if it doesn't exist
if ! docker network ls --filter driver=overlay --format '{{.Name}}' | grep -q "^$NETWORK$"; then
  echo "🔧 Creating Swarm overlay network '$NETWORK'..."
  docker network create --driver overlay "$NETWORK"
fi

RN_CONTACT_NODE_ID="${REGION}_node_1"
RN_CONTACT_NODE_ADDR="${REGION}_node_1:6001"
GN_CONTACT_NODE_ID="${GN_REGION}_node_1"
GN_CONTACT_NODE_ADDR="${GN_REGION}_node_1:7001"

for i in $(seq "$INDEX" "$(($INDEX + $COUNT - 1))"); do
  NAME="${REGION}_node_$i"
  SERVICE_NAME="$NAME"
  HOST_PROM_PORT=$((9090 + PORT_OFFSET + i))
  GENERATOR_PORT=$((10000 + PORT_OFFSET + i))
  HOST_MC_PORT=$((5000 + PORT_OFFSET + i))
  LOG="log/${NAME}"

  HTTP_SERVER_ADDR="${NAME}:5001"
  RN_LISTEN_ADDR="${NAME}:6001"
  GN_LISTEN_ADDR="${NAME}:7001"
  RRN_LISTEN_ADDR="${NAME}:8001"

  mkdir -p "$LOG/results"

  echo "🚀 Deploying service $SERVICE_NAME..."

  docker service create \
    --name "$SERVICE_NAME" \
    --hostname "$NAME" \
    --network "$NETWORK" \
    --env-file .env \
    --env NODE_REGION="$REGION" \
    --env NODE_ID="$NAME" \
    --env RN_CONTACT_NODE_ID="$RN_CONTACT_NODE_ID" \
    --env RN_CONTACT_NODE_ADDR="$RN_CONTACT_NODE_ADDR" \
    --env GN_CONTACT_NODE_ID="$GN_CONTACT_NODE_ID" \
    --env GN_CONTACT_NODE_ADDR="$GN_CONTACT_NODE_ADDR" \
    --env HTTP_SERVER_ADDR="$HTTP_SERVER_ADDR" \
    --env RN_LISTEN_ADDR="$RN_LISTEN_ADDR" \
    --env GN_LISTEN_ADDR="$GN_LISTEN_ADDR" \
    --env RRN_LISTEN_ADDR="$RRN_LISTEN_ADDR" \
    --mount type=bind,src="$(pwd)/${LOG}",dst=/var/log/monoceros \
    --publish published="$HOST_PROM_PORT",target=9090 \
    --publish published="$HOST_MC_PORT",target=5001 \
    --publish published="$GENERATOR_PORT",target=9100 \
    "$IMAGE"

  sleep 1

  # Update contact info for next node
  count_gn=$(docker service ls --format '{{.Name}}' | grep -c "^$GN_REGION")
  rand_gn=$((1 + RANDOM % count_gn))

  count_rn=$(docker service ls --format '{{.Name}}' | grep -c "^$REGION")
  rand_rn=$((1 + RANDOM % count_rn))

  GN_PREV_NODE_NAME="${GN_REGION}_node_${rand_gn}"
  RN_PREV_NODE_NAME="${REGION}_node_${rand_rn}"

  RN_CONTACT_NODE_ID="$RN_PREV_NODE_NAME"
  RN_CONTACT_NODE_ADDR="${RN_PREV_NODE_NAME}:6001"

  GN_CONTACT_NODE_ID="$GN_PREV_NODE_NAME"
  GN_CONTACT_NODE_ADDR="${GN_PREV_NODE_NAME}:7001"
done

echo "✅ Started $COUNT services with REGION=$REGION."
date +%s > ts.txt
