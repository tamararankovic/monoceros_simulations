#!/usr/bin/bash
# stop_percent.sh — Stops N% of running Docker containers whose names start with a given prefix.
#
# USAGE:
#   ./stop_percent.sh <percent> <prefix>
#
# EXAMPLES:
#   ./stop_percent.sh 30 eu-west_   # stop 30% of containers starting with "eu-west_"
#   ./stop_percent.sh 50 ""         # stop 50% of all running containers

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

# Get list of matching container names
if [[ -z "$PREFIX" ]]; then
  CONTAINERS=( $(docker ps --format '{{.Names}}') )
else
  CONTAINERS=( $(docker ps --format '{{.Names}}' | grep "^$PREFIX") )
fi

# Shuffle
CONTAINERS=( $(printf "%s\n" "${CONTAINERS[@]}" | gshuf) )

TOTAL=${#CONTAINERS[@]}

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No matching containers found."
  exit 0
fi

# Calculate how many to stop
COUNT=$(( (TOTAL * PERCENT + 99) / 100 ))  # rounded up
TO_STOP=( "${CONTAINERS[@]:0:$COUNT}" )

echo "⛔ Stopping $COUNT of $TOTAL containers matching prefix '$PREFIX'..."

for name in "${TO_STOP[@]}"; do
  echo "🔻 Stopping $name..."
  docker stop "$name" > /dev/null
done

echo "✅ Done."
