#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <num_nodes> <num_regions> <intraregional_latency> <interregional_latency> <exp_name>"
  exit 1
fi

NODES="$1"
REGIONS="$2"
INTRA_LATENCY="$3"
INTER_LATENCY="$4"
EXP_NAME="$5"

bash start_net.sh $NODES $REGIONS $INTRA_LATENCY $INTER_LATENCY
bash start_ep.sh $NODES $REGIONS $INTRA_LATENCY $INTER_LATENCY $EXP_NAME