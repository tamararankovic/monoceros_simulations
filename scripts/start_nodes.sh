#!/usr/bin/env bash
# start_nodes.sh — Starts N Docker containers from a given image, with region-based naming.
#
# USAGE:
#   ./start_nodes.sh <image_name> <number_of_nodes> <region> <global-network-contact-id> <global-network-contact-address>
#
# EXAMPLE:
#   ./start_nodes.sh mynodeimage 5 eu-west eu-east_node_1 eu-east_node_1:7001
#
# This starts: eu-west_node_1, eu-west_node_2, ..., each with ENV REGION=eu-west

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <image_name> <number_of_nodes> <region> <global-network-contact-id> <global-network-contact-address>"
  exit 1
fi

IMAGE="$1"
COUNT="$2"
REGION="$3"
GN_CONTACT_NODE_ID="$4"
GN_CONTACT_NODE_ADDR="$5"
NETWORK="p2pnet"

# Create Docker network if it doesn't already exist
if ! docker network ls --format '{{.Name}}' | grep -q "^$NETWORK$"; then
  echo "🔧 Creating Docker network '$NETWORK'..."
  docker network create "$NETWORK"
fi

FIRST_NODE_NAME="${REGION}_node_1"
RN_CONTACT_NODE_ID="$FIRST_NODE_NAME"
RN_CONTACT_NODE_ADDR="${FIRST_NODE_NAME}:6001"

for i in $(seq 1 "$COUNT"); do
  NAME="${REGION}_node_$i"
  NODE_ID="node_$i"
  echo "🚀 Starting container $NAME from image $IMAGE..."
  docker run -dit \
    --name "$NAME" \
    --hostname "$NAME" \
    --network "$NETWORK" \
    --env-file .env \
    -e NODE_REGION="$REGION" \
    -e NODE_ID="$NODE_ID" \
    -e RN_CONTACT_NODE_ID="$RN_CONTACT_NODE_ID" \
    -e RN_CONTACT_NODE_ADDR="$RN_CONTACT_NODE_ADDR" \
    -e GN_CONTACT_NODE_ID="$GN_CONTACT_NODE_ID" \
    -e GN_CONTACT_NODE_ADDR="$GN_CONTACT_NODE_ADDR" \
    "$IMAGE"
done

echo "✅ Started $COUNT containers with REGION=$REGION."
