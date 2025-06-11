#!/usr/bin/env bash
# start_nodes.sh — Starts N Docker containers with region-based naming.
#
# USAGE:
#   ./start_nodes.sh <number_of_nodes> <region> <global-network-contact-id> <global-network-contact-address>
#
# EXAMPLE:
#   ./start_nodes.sh monoceros-all 5 r1 r1_node_1 r1_node_1:7001 0
#
# This starts: eu-west_node_1, eu-west_node_2, ..., each with ENV REGION=eu-west

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 <number_of_nodes> <region> <global-network-contact-id> <global-network-contact-address> <port_offset> <index>"
  exit 1
fi

COUNT="$1"
REGION="$2"
GN_CONTACT_NODE_ID="$3"
GN_CONTACT_NODE_ADDR="$4"
PORT_OFFSET="$5"
INDEX="$6"
NETWORK="p2pnet"
IMAGE="monoceros-all"

cd ../../
docker build -t "$IMAGE" -f monoceros_simulations/Dockerfile .
cd monoceros_simulations/scripts

# Create Docker network if it doesn't already exist
if ! docker network ls --format '{{.Name}}' | grep -q "^$NETWORK$"; then
  echo "🔧 Creating Docker network '$NETWORK'..."
  docker network create "$NETWORK"
fi

PREV_NODE_NAME="${REGION}_node_1"
RN_CONTACT_NODE_ID="$PREV_NODE_NAME"
RN_CONTACT_NODE_ADDR="${PREV_NODE_NAME}:6001"
GN_CONTACT_NODE_ID="$PREV_NODE_NAME"
GN_CONTACT_NODE_ADDR="${PREV_NODE_NAME}:7001"

echo $PREV_NODE_NAME
echo $RN_CONTACT_NODE_ID
echo $RN_CONTACT_NODE_ADDR

for i in $(seq "$(($INDEX))" "$(($INDEX + $COUNT -1))"); do
  NAME="${REGION}_node_$i"
  HOST_PROM_PORT=$((9090 + PORT_OFFSET + i))
  HOST_MC_PORT=$((5000 + PORT_OFFSET + i))
  LOG="log/${NAME}"

  HTTP_SERVER_ADDR="${NAME}:5001"
  RN_LISTEN_ADDR="${NAME}:6001"
  GN_LISTEN_ADDR="${NAME}:7001"
  RRN_LISTEN_ADDR="${NAME}:8001"

  mkdir -p $LOG
  echo "🚀 Starting container $NAME from image $IMAGE..."
  docker run -dit \
    --name "$NAME" \
    --hostname "$NAME" \
    --network "$NETWORK" \
    --env-file .env \
    -e NODE_REGION="$REGION" \
    -e NODE_ID="$NAME" \
    -e RN_CONTACT_NODE_ID="$RN_CONTACT_NODE_ID" \
    -e RN_CONTACT_NODE_ADDR="$RN_CONTACT_NODE_ADDR" \
    -e GN_CONTACT_NODE_ID="$GN_CONTACT_NODE_ID" \
    -e GN_CONTACT_NODE_ADDR="$GN_CONTACT_NODE_ADDR" \
    -e HTTP_SERVER_ADDR="$HTTP_SERVER_ADDR" \
    -e RN_LISTEN_ADDR="$RN_LISTEN_ADDR" \
    -e GN_LISTEN_ADDR="$GN_LISTEN_ADDR" \
    -e RRN_LISTEN_ADDR="$RRN_LISTEN_ADDR" \
    -p "$HOST_PROM_PORT:9090" \
    -p "$HOST_MC_PORT:5001" \
    -v "$(pwd)/${LOG}:/var/log/monoceros" \
    "$IMAGE"

  sleep 0.5
  rand=$((1 + RANDOM % i))
  PREV_NODE_NAME="${REGION}_node_$((rand))"
  RN_CONTACT_NODE_ID="$PREV_NODE_NAME"
  RN_CONTACT_NODE_ADDR="${PREV_NODE_NAME}:6001"
  GN_CONTACT_NODE_ID="$PREV_NODE_NAME"
  GN_CONTACT_NODE_ADDR="${PREV_NODE_NAME}:7001"
  # if [[ "$i" -eq 1 ]]; then
  #   sleep 10
  # fi
  # sleep 5
done

echo "✅ Started $COUNT containers with REGION=$REGION."
