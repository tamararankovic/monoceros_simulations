#!/usr/bin/env bash
# stop_percent.sh — Scales down N% of Swarm services whose names start with a given prefix.
#
# USAGE:
#   ./stop_percent.sh <percent> <prefix>
#
# EXAMPLES:
#   ./stop_percent.sh 30 r1_     # scale down 30% of services starting with "r1_"
#   ./stop_percent.sh 50 ""      # scale down 50% of all *_node_* services

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <percent> <prefix>"
  exit 1
fi

PERCENT="$1"
PREFIX="$2"

# Validate percent
if ! [[ "$PERCENT" =~ ^[0-9]+$ ]] || [[ "$PERCENT" -lt 1 || "$PERCENT" -gt 100 ]]; then
  echo "Error: percent must be an integer between 1 and 100"
  exit 1
fi

# Get list of matching services
if [[ -z "$PREFIX" ]]; then
  SERVICES=( $(docker service ls --format '{{.Name}}' | grep '_node_') )
else
  SERVICES=( $(docker service ls --format '{{.Name}}' | grep "^$PREFIX") )
fi

if [[ "${#SERVICES[@]}" -eq 0 ]]; then
  echo "No matching services found."
  exit 0
fi

# Shuffle
SERVICES=( $(printf "%s\n" "${SERVICES[@]}" | shuf) )

TOTAL=${#SERVICES[@]}
COUNT=$(( (TOTAL * PERCENT + 99) / 100 ))  # round up
TO_STOP=( "${SERVICES[@]:0:$COUNT}" )

echo "⛔ Scaling down $COUNT of $TOTAL services matching prefix '$PREFIX'..."

for name in "${TO_STOP[@]}"; do
  echo "🔻 Scaling $name to 0 replicas..."
  docker service scale "$name=0" > /dev/null
done

echo "✅ Done."
date +%s > ts.txt
