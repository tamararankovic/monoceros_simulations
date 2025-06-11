#!/usr/bin/env bash
# cleanup_nodes.sh — Stops and removes all containers matching *_node_*

docker ps -a --format '{{.Names}}' | grep '_node_' | xargs -r docker rm -f