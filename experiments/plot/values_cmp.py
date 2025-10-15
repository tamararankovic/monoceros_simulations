#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]
BASE_DIR = Path("/home/tamara/experiments/results")
prefixes = ["fu", "mc", "dd", "ep", "rr"]

def compute_average_values(exp_name: str, common_index: pd.Index) -> pd.DataFrame:
    """
    Compute expected and measured values averaged across nodes and repetitions,
    aligned to a common index.
    Returns a DataFrame with columns ["expected", "measured"].
    """
    exp_dir = BASE_DIR / exp_name
    repetitions = sorted(exp_dir.glob("exp_*"))
    expected_all, measured_all = [], []

    for rep_dir in repetitions:
        # --- Expected values ---
        expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
        expected_df["ts_rcvd"] = expected_df["ts_rcvd"].astype(int)
        expected_df = expected_df.drop_duplicates(subset="ts_rcvd").set_index("ts_rcvd")
        expected_df = expected_df.reindex(common_index).ffill().bfill()
        expected_all.append(expected_df["value"])

        # --- Measured: average across nodes ---
        node_files = sorted(rep_dir.glob("*/normalized_values.csv"))
        node_dfs = []
        for f in node_files:
            node_df = pd.read_csv(f)
            node_df["ts_rcvd"] = node_df["ts_rcvd"].astype(int)
            node_df = node_df.drop_duplicates(subset="ts_rcvd").set_index("ts_rcvd")

            first_ts = node_df.index.min()
            last_ts = node_df.index.max()
            mask = (common_index >= first_ts) & (common_index <= last_ts)
            selected_index = common_index[mask]

            node_df = node_df.reindex(selected_index)
            node_dfs.append(node_df)

        if node_dfs:
            measured_df = pd.concat(node_dfs, axis=1).mean(axis=1).to_frame(name="value")
            measured_all.append(measured_df["value"])

    # --- Average across repetitions ---
    expected_avg = pd.concat(expected_all, axis=1).mean(axis=1)
    measured_avg = pd.concat(measured_all, axis=1).mean(axis=1)

    return pd.DataFrame({"expected": expected_avg, "measured": measured_avg}, index=common_index)

def get_full_index(exp_names):
    ts_all = []
    for exp_name in exp_names:
        exp_dir = BASE_DIR / exp_name
        repetitions = sorted(exp_dir.glob("exp_*"))
        for rep_dir in repetitions:
            expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
            ts_all.extend(expected_df["ts_rcvd"].astype(int).values)
    return pd.Index(sorted(set(ts_all)), dtype=int)

# --- Build common index for all prefixes ---
exp_names = [f"{prefix}_{experiment_name}" for prefix in prefixes]
common_index = get_full_index(exp_names).astype(int)  # ensure numeric for plotting

# --- Compute values for all prefixes ---
values_dict = {}
for prefix in prefixes:
    values_dict[prefix] = compute_average_values(f"{prefix}_{experiment_name}", common_index).ffill()
    values_dict[prefix]["expected"] = values_dict[prefix]["expected"].round(4)
    values_dict[prefix]["measured"] = values_dict[prefix]["measured"].round(4)

# --- Plot ---
plt.figure(figsize=(10, 6))

# Assign colors and line styles for clarity
colors = {
    "fu": "orange",
    "mc": "red",
    "dd": "purple",
    "ep": "brown",
    "rr": "green"
}

for prefix in prefixes:
    plt.plot(common_index, values_dict[prefix]["expected"], label=f"{prefix.upper()} Expected",
             linestyle="--", color=colors[prefix])
    plt.plot(common_index, values_dict[prefix]["measured"], label=f"{prefix.upper()} Measured",
             color=colors[prefix])

plt.xlabel("Time (s)")
plt.ylabel("Value")
plt.title("Measured vs Expected Values")
plt.ticklabel_format(useOffset=False, style='plain', axis='y')
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_values.svg")
plt.close()
