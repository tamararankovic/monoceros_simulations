#!/usr/bin/env python3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

exp_name = sys.argv[1]
base_dir = Path(f"/home/tamara/experiments/results/{exp_name}")

# Find all repetition directories
repetitions = sorted([d for d in base_dir.iterdir() if d.is_dir() and d.name.startswith("exp_")])
all_errors = []

for rep_dir in repetitions:
    expected_file = rep_dir / "normalized_expected_values.csv"
    if not expected_file.exists():
        continue
    expected_df = pd.read_csv(expected_file)

    # Collect all node values
    node_dirs = [d for d in rep_dir.iterdir() if d.is_dir()]
    node_values_list = []
    for node_dir in node_dirs:
        node_file = node_dir / "normalized_values.csv"
        if node_file.exists():
            node_values_list.append(pd.read_csv(node_file))

    if not node_values_list:
        continue

    # Average measured values across nodes
    measured_df = pd.concat(node_values_list).groupby("ts_rcvd").mean()

    # Align indices with expected values
    df = expected_df.set_index("ts_rcvd").join(measured_df, lsuffix="_exp", rsuffix="_meas")

    # Calculate percentage error per timestamp
    df["perc_error"] = np.abs(df["value_meas"] - df["value_exp"]) / df["value_exp"] * 100
    all_errors.append(df["perc_error"])

if not all_errors:
    print("No data found for experiment:", exp_name)
    sys.exit(1)

# Concatenate all repetitions
errors_df = pd.concat(all_errors, axis=1)

# Average across repetitions
avg_error = errors_df.mean(axis=1)

# Round timestamps and errors to 4 decimals
avg_error.index = avg_error.index.round(4)
avg_error = avg_error.round(4)

# Plot
plt.figure(figsize=(10, 6))
plt.plot(avg_error.index, avg_error.values)  # convert ms → seconds
plt.xlabel("Time (s)")
plt.ylabel("Average Percentage Error (%)")
plt.title(f"Average Percentage Error Across Repetitions: {exp_name}")
plt.grid(True)
plt.ticklabel_format(useOffset=False, style='plain', axis='y')
plt.tight_layout()

# Save plot
out_file = base_dir / "avg_percentage_error.svg"
plt.savefig(out_file)
plt.close()

print("Plot saved to", out_file)
