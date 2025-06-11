#!/usr/bin/env bash
# chaos_live_links.sh — Disables N random *active* links between containers for X seconds.
#
# USAGE:
#   sudo ./chaos_live_links.sh <num_links> <duration_secs> [name_prefix]
#
# NOTES:
#   • Requires link.sh in the same directory.
#   • Only considers container pairs with established TCP connections.

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <num_links> <duration_secs> [name_prefix]"
  exit 1
fi

NUM_LINKS=$1
DURATION=$2
PREFIX="${3:-}"
LINK_SH="$(dirname "$0")/link.sh"

[[ -x "$LINK_SH" ]] || { echo "❌ link.sh not found or not executable."; exit 1; }

########################################
# Get all container names (optionally filtered by prefix)
########################################
if [[ -n "$PREFIX" ]]; then
  readarray -t CONTAINERS < <(docker ps --format '{{.Names}}' | grep "^$PREFIX")
else
  readarray -t CONTAINERS < <(docker ps --format '{{.Names}}')
fi

if (( ${#CONTAINERS[@]} < 2 )); then
  echo "❌ Need at least 2 containers to find links."
  exit 1
fi

########################################
# Map container name -> IP
########################################
declare -A CONTAINER_IPS
for c in "${CONTAINERS[@]}"; do
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
  CONTAINER_IPS["$c"]="$ip"
done

########################################
# Check for live TCP links (established connections)
########################################
declare -A LINKED_PAIRS=()
for a in "${CONTAINERS[@]}"; do
  ip_a="${CONTAINER_IPS[$a]}"
  for b in "${CONTAINERS[@]}"; do
    [[ "$a" == "$b" ]] && continue
    ip_b="${CONTAINER_IPS[$b]}"

    # Does A have any TCP connections to B?
    if docker exec "$a" ss -tn | awk '{print $5}' | grep -q "^$ip_b:"; then
      key=$(printf "%s %s\n" "$a" "$b" | sort)  # sort to avoid duplicates (unordered pair)
      LINKED_PAIRS["$key"]=1
    fi
  done
done

LINKS=("${!LINKED_PAIRS[@]}")
TOTAL_LINKS=${#LINKS[@]}

if (( TOTAL_LINKS == 0 )); then
  echo "❌ No active connections found between containers."
  exit 0
fi

if (( NUM_LINKS > TOTAL_LINKS )); then
  echo "⚠️  Requested $NUM_LINKS links but only $TOTAL_LINKS active connections found."
  NUM_LINKS=$TOTAL_LINKS
fi

########################################
# Randomly pick N links
########################################
readarray -t SELECTED < <(printf '%s\n' "${LINKS[@]}" | shuf -n "$NUM_LINKS")

restore_links () {
  echo "🔄 Restoring links..."
  for pair in "${SELECTED[@]}"; do
    set -- $pair
    "$LINK_SH" on "$1" "$2" || true
  done
}
trap restore_links EXIT

echo "⛔ Cutting ${#SELECTED[@]} active links for $DURATION seconds:"
for pair in "${SELECTED[@]}"; do
  set -- $pair
  echo "   • $1 ↔ $2"
  "$LINK_SH" off "$1" "$2"
done

sleep "$DURATION"

echo "⏰ Time's up."
restore_links
trap - EXIT
echo "✅ All links restored."
