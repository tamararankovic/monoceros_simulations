#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <experiment_name>"
    exit 1
fi

exp_name="$1"

DEST_DIR="$HOME/Documents/monitoring/impl/monoceros_simulations/experiments/plot/results/${exp_name}"
mkdir -p "$DEST_DIR"

scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_rmse.svg" "$DEST_DIR/error.svg"
scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_msg_count.svg" "$DEST_DIR/msg_count.svg"
scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_msg_rate.svg" "$DEST_DIR/msg_rate.svg"
scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_values.svg" "$DEST_DIR/values.svg"
scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_per_node_values_exp1_1s.svg" "$DEST_DIR/values_scatter.svg"
