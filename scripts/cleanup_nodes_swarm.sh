#!/usr/bin/env bash
# cleanup_nodes.sh — Removes all Swarm services matching *_node_*

set -euo pipefail

echo "🧹 Removing Swarm services matching '*_node_*'..."

services=$(docker service ls --format '{{.Name}}' | grep '_node_') || true

if [[ -z "$services" ]]; then
  echo "ℹ️ No matching services found."
  exit 0
fi

echo "$services" | xargs -r docker service rm

echo "✅ All matching services removed."
