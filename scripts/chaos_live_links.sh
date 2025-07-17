#!/opt/homebrew/bin/bash
# chaos_live_links.sh — Disables N random *active* TCP links between Docker containers for X seconds.
#
# USAGE:
#   sudo ./chaos_live_links.sh <num_links> <duration_secs> [name_prefix]
#
# REQUIREMENTS:
#   • Containers must support netstat (part of net-tools).
#   • Only affects containers with established TCP connections.
#   • Must be run with sudo.

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <num_links> <duration_secs> [name_prefix]"
  exit 1
fi

NUM_LINKS=$1
DURATION=$2
PREFIX=${3:-}

echo "🔍 Finding containers${PREFIX:+ with prefix '$PREFIX'}..."
if [[ -n "$PREFIX" ]]; then
  CONTAINERS=($(docker ps --format '{{.Names}}' | grep "^$PREFIX"))
else
  CONTAINERS=($(docker ps --format '{{.Names}}'))
fi

if (( ${#CONTAINERS[@]} < 2 )); then
  echo "❌ Need at least 2 containers to work with."
  exit 1
fi

echo "🔌 Mapping container IPs..."
declare -A IPS
for c in "${CONTAINERS[@]}"; do
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
  IPS["$c"]=$ip
done

echo "🌐 Scanning for active TCP connections using netstat..."
declare -A LIVE_PAIRS
for a in "${CONTAINERS[@]}"; do
  ip_a="${IPS[$a]}"
  for b in "${CONTAINERS[@]}"; do
    [[ "$a" == "$b" ]] && continue
    ip_b="${IPS[$b]}"
    # Check if netstat output in container $a includes destination $ip_b
    if docker exec "$a" netstat -tn | awk '{print $5}' | grep -q "^$ip_b:"; then
      key=$(echo -e "$a\n$b" | sort | tr '\n' ' ')
      LIVE_PAIRS["$key"]=1
    fi
  done
done

LINKS=("${!LIVE_PAIRS[@]}")
TOTAL_LINKS=${#LINKS[@]}

if (( TOTAL_LINKS == 0 )); then
  echo "❌ No live TCP connections between containers."
  exit 0
fi

if (( NUM_LINKS > TOTAL_LINKS )); then
  echo "⚠️  Requested $NUM_LINKS links, but only $TOTAL_LINKS available. Reducing..."
  NUM_LINKS=$TOTAL_LINKS
fi

readarray -t SELECTED < <(printf '%s\n' "${LINKS[@]}" | shuf -n "$NUM_LINKS")

block_links () {
  for pair in "${SELECTED[@]}"; do
    read -r a b <<< "$pair"
    ip_a="${IPS[$a]}"
    ip_b="${IPS[$b]}"
    echo "⛔ Blocking TCP: $a ↔ $b"
    docker exec "$a" iptables -A OUTPUT -d "$ip_b" -p tcp -j DROP
    docker exec "$b" iptables -A OUTPUT -d "$ip_a" -p tcp -j DROP
  done
}

restore_links () {
  echo "🔄 Restoring links..."
  for pair in "${SELECTED[@]}"; do
    read -r a b <<< "$pair"
    ip_a="${IPS[$a]}"
    ip_b="${IPS[$b]}"
    docker exec "$a" iptables -D OUTPUT -d "$ip_b" -p tcp -j DROP || true
    docker exec "$b" iptables -D OUTPUT -d "$ip_a" -p tcp -j DROP || true
  done
}

trap restore_links EXIT

block_links
echo "🕒 Waiting $DURATION seconds..."
sleep "$DURATION"
echo "✅ Time's up. Restoring connectivity."
restore_links
trap - EXIT
