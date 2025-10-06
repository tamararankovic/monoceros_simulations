#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <experiment_name>"
    exit 1
fi

exp_name="$1"

# Destination directory
dest_dir=~/Documents/monitoring/impl/monoceros_simulations/experiments/plot/results/"$exp_name"

# Make sure destination directory exists
mkdir -p "$dest_dir"

# Copy RMSE SVG from remote host
scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_rmse.svg" "$dest_dir/rmse.svg"

echo "Copied ${exp_name}_rmse.svg to $dest_dir"

scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_values.svg" "$dest_dir/value.svg"

echo "Copied ${exp_name}_value.svg to $dest_dir"

scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_msg_count.svg" "$dest_dir/msg_count.svg"

echo "Copied ${exp_name}_msg_count.svg to $dest_dir"

scp "nova_cluster:/home/tamara/experiments/results/${exp_name}_msg_rate.svg" "$dest_dir/msg_rate.svg"

echo "Copied ${exp_name}_msg_rate.svg to $dest_dir"
