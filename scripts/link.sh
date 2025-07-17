#!/usr/bin/env bash
# link.sh  ── turn the link between two Docker containers ON or OFF
#
# USAGE:
#   sudo ./link.sh off <containerA> <containerB>   # cut the link
#   sudo ./link.sh on  <containerA> <containerB>   # restore the link
#
# REQUIREMENTS:
#   • The containers run on the same Linux host.
#   • Both containers have the iptables binary (most full Linux images do).
#   • The user running this script can execute `docker exec` (is in the docker group or root).

set -euo pipefail

if [[ $# -ne 3 || ! "$1" =~ ^(on|off)$ ]]; then
  echo "Usage: $0 <on|off> <containerA> <containerB>"
  exit 1
fi

MODE=$1
C1=$2
C2=$3

# helper: fetch the primary IP address of a container
get_ip () {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

IP1=$(get_ip "$C1")
IP2=$(get_ip "$C2")

apply_rule () {
  local cont="$1" direction="$2" addr="$3" action="$4"
  # INPUT rules target traffic coming *from* addr, OUTPUT rules target traffic *to* addr
  if [[ "$direction" == "INPUT" ]]; then match="-s $addr"; else match="-d $addr"; fi
  if [[ "$action" == "add" ]]; then
    docker exec "$cont" sh -c "iptables -C $direction $match -j DROP 2>/dev/null || iptables -A $direction $match -j DROP"
  else # delete
    docker exec "$cont" sh -c "iptables -D $direction $match -j DROP 2>/dev/null || true"
  fi
}

if [[ "$MODE" == "off" ]]; then
  echo "⛔  Disabling link between $C1 ($IP1) and $C2 ($IP2)…"
  apply_rule "$C1" OUTPUT "$IP2" add
  apply_rule "$C1" INPUT  "$IP2" add
  apply_rule "$C2" OUTPUT "$IP1" add
  apply_rule "$C2" INPUT  "$IP1" add
  echo "✅  Link disabled."
else
  echo "🔄  Restoring link between $C1 ($IP1) and $C2 ($IP2)…"
  apply_rule "$C1" OUTPUT "$IP2" del
  apply_rule "$C1" INPUT  "$IP2" del
  apply_rule "$C2" OUTPUT "$IP1" del
  apply_rule "$C2" INPUT  "$IP1" del
  echo "✅  Link restored."
fi
