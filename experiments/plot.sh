#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <experiment_name>"
    exit 1
fi

exp_name="$1"

# --- Go to analyze directory and run Python scripts ---
cd ./analyze

echo "Running values.py for FU and MC..."
python3 "values.py" "fu_${exp_name}"
python3 "values.py" "mc_${exp_name}"

echo "Running msg_count.py for FU and MC..."
python3 "msg_count.py" "fu_${exp_name}"
python3 "msg_count.py" "mc_${exp_name}"

# --- Go to plot directory and run comparison scripts ---
cd ../plot

echo "Running comparison scripts..."
python3 "values_cmp.py" "$exp_name"
python3 "error_cmp.py" "$exp_name"
python3 "msg_count_cmp.py" "$exp_name"

echo "All analysis and plotting done for experiment: $exp_name"
