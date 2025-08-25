#!/usr/bin/env bash
# cleanup_nodes.sh — Stops and removes all containers matching *_node_*

docker ps -a --format '{{.Names}}' | grep '_node_' | while read name; do docker logs "$name" > "log/$name/output.log" 2>&1; done
docker ps -a --format '{{.Names}}' | grep '_node_' | xargs -r docker rm -f