#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import sys
from pathlib import Path
from matplotlib.lines import Line2D

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]
BASE_DIR = Path("/home/tamara/experiments/results")
prefixes = ["fu", "mc", "dd", "ep", "rr"]

# Assign colors for each algorithm
node_colors = {
    "fu": "orange",
    "mc": "red",
    "dd": "purple",
    "ep": "brown",
    "rr": "cyan"
}
expected_colors = {
    "fu": "blue",
    "mc": "green",
    "dd": "magenta",
    "ep": "olive",
    "rr": "teal"
}

def get_exp1_index(exp_name):
    ts_all = []
    for prefix in prefixes:
        rep_dir = BASE_DIR / f"{prefix}_{exp_name}" / "exp_1"
        expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
        ts_all.extend(expected_df["ts_rcvd"].values)
    return pd.Index(sorted(set(ts_all)))

def get_per_node_values(exp_name, prefix, common_index):
    rep_dir = BASE_DIR / f"{prefix}_{exp_name}" / "exp_1"
    node_files = sorted(rep_dir.glob("*/normalized_values.csv"))
    node_dfs = []

    for f in node_files:
        node_df = pd.read_csv(f)
        node_df.set_index("ts_rcvd", inplace=True)
        node_name = f.parent.name
        node_df = node_df.rename(columns={"value": node_name})
        node_dfs.append(node_df)

    if node_dfs:
        return pd.concat(node_dfs, axis=1)
    else:
        return pd.DataFrame(index=common_index)

def get_expected_values(exp_name, prefix, common_index):
    rep_dir = BASE_DIR / f"{prefix}_{exp_name}" / "exp_1"
    expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
    expected_df.set_index("ts_rcvd", inplace=True)
    return expected_df["value"]

def downsample_1s(index_float, df_or_series):
    keep_idx = [0]  # always keep first point
    last_t = index_float[0]
    for i, t in enumerate(index_float[1:], start=1):
        if t - last_t >= 1.0:
            keep_idx.append(i)
            last_t = t
    if isinstance(df_or_series, pd.DataFrame):
        return df_or_series.iloc[keep_idx], index_float[keep_idx]
    else:
        return df_or_series.iloc[keep_idx], index_float[keep_idx]

# --- Main ---
common_index = get_exp1_index(experiment_name)

per_node_data = {}
expected_data = {}

# Load per-node and expected values for all prefixes
for prefix in prefixes:
    per_node_data[prefix] = get_per_node_values(experiment_name, prefix, common_index)
    expected_data[prefix] = get_expected_values(experiment_name, prefix, common_index)

# Downsample all
per_node_ds = {}
index_ds = {}
expected_ds = {}
expected_index_ds = {}

for prefix in prefixes:
    df = per_node_data[prefix]
    idx = df.index.values
    df_ds, idx_ds = downsample_1s(idx, df)
    per_node_ds[prefix] = df_ds
    index_ds[prefix] = idx_ds

    exp_series = expected_data[prefix]
    exp_idx = exp_series.index.values
    exp_ds, exp_idx_ds = downsample_1s(exp_idx, exp_series)
    expected_ds[prefix] = exp_ds
    expected_index_ds[prefix] = exp_idx_ds

# --- Plot ---
plt.figure(figsize=(12,6))

# Scatter per-node values
for prefix in prefixes:
    df = per_node_ds[prefix]
    idx = index_ds[prefix]
    for col in df.columns:
        plt.scatter(idx, df[col], s=10, alpha=0.6, color=node_colors[prefix])

# Expected values as thin dashed lines
for prefix in prefixes:
    plt.plot(expected_index_ds[prefix], expected_ds[prefix].values,
             color=expected_colors[prefix], linestyle="--", linewidth=1)

# Legend
legend_elements = []
for prefix in prefixes:
    legend_elements.append(Line2D([0], [0], marker='o', color='w', label=f'{prefix.upper()} nodes',
                                  markerfacecolor=node_colors[prefix], markersize=6))
    legend_elements.append(Line2D([0], [0], color=expected_colors[prefix], lw=1, linestyle='--',
                                  label=f'{prefix.upper()} expected'))

plt.legend(handles=legend_elements)
plt.xlabel("Time (s)")
plt.ylabel("Value")
plt.title("Per-Node Values with Expected Line (exp_1)")
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_per_node_values_exp1_1s.svg")
plt.close()
