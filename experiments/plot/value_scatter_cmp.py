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


# def reindex_with_limits(df: pd.DataFrame, common_index: pd.Index) -> pd.DataFrame:
#     """
#     Reindex df to common_index but only ffill/bfill within original index range.
#     Values outside original min/max are left as NaN.
#     """
#     if df.empty:
#         return pd.DataFrame(index=common_index, columns=df.columns)
    
#     orig_min = df.index.min()
#     orig_max = df.index.max()

#     # Reindex to common_index
#     df_re = df.reindex(common_index)

#     # Forward-fill only within original range
#     mask = (df_re.index >= orig_min) & (df_re.index <= orig_max)
#     df_re.loc[mask] = df_re.loc[mask].ffill()
#     df_re.loc[mask] = df_re.loc[mask].bfill()

#     return df_re


def get_exp1_index(exp_name):
    ts_all = []
    for prefix in ["fu", "mc"]:
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
        # node_df = reindex_with_limits(node_df, common_index)
        node_dfs.append(node_df)

    if node_dfs:
        return pd.concat(node_dfs, axis=1)
    else:
        return pd.DataFrame(index=common_index)


def get_expected_values(exp_name, prefix, common_index):
    rep_dir = BASE_DIR / f"{prefix}_{exp_name}" / "exp_1"
    expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
    expected_df.set_index("ts_rcvd", inplace=True)
    expected_df = expected_df.rename(columns={"value": "value"})
    # expected_df = reindex_with_limits(expected_df, common_index)
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

fu_nodes = get_per_node_values(experiment_name, "fu", common_index)
mc_nodes = get_per_node_values(experiment_name, "mc", common_index)

fu_expected = get_expected_values(experiment_name, "fu", common_index)
mc_expected = get_expected_values(experiment_name, "mc", common_index)

# Convert milliseconds to seconds
fu_index_sec = fu_nodes.index.values
mc_index_sec = mc_nodes.index.values
fu_expected_index_sec = fu_expected.index.values
mc_expected_index_sec = mc_expected.index.values

# Downsample to roughly 1 second apart
fu_nodes_ds, fu_index_sec_ds = downsample_1s(fu_index_sec, fu_nodes)
mc_nodes_ds, mc_index_sec_ds = downsample_1s(mc_index_sec, mc_nodes)
fu_expected_ds, fu_expected_index_ds = downsample_1s(fu_expected_index_sec, fu_expected)
mc_expected_ds, mc_expected_index_ds = downsample_1s(mc_expected_index_sec, mc_expected)

# --- Plot ---
plt.figure(figsize=(12,6))

# Scatter per-node values
for col in fu_nodes_ds.columns:
    plt.scatter(fu_index_sec_ds, fu_nodes_ds[col], s=10, alpha=0.6, color="orange")
for col in mc_nodes_ds.columns:
    plt.scatter(mc_index_sec_ds, mc_nodes_ds[col], s=10, alpha=0.6, color="red")

# Expected values as thin dashed lines
plt.plot(fu_expected_index_ds, fu_expected_ds.values, color="blue", linestyle="--", linewidth=1)
plt.plot(mc_expected_index_ds, mc_expected_ds.values, color="green", linestyle="--", linewidth=1)

# Add legend for algorithm colors only
from matplotlib.lines import Line2D
legend_elements = [
    Line2D([0], [0], marker='o', color='w', label='FU nodes', markerfacecolor='orange', markersize=6),
    Line2D([0], [0], marker='o', color='w', label='MC nodes', markerfacecolor='red', markersize=6),
    Line2D([0], [0], color='blue', lw=1, linestyle='--', label='FU expected'),
    Line2D([0], [0], color='green', lw=1, linestyle='--', label='MC expected'),
]
plt.legend(handles=legend_elements)

plt.xlabel("Time (s)")
plt.ylabel("Value")
plt.title("Per-Node Values with Expected Line (Flow Updating vs Monoceros, exp_1)")
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_per_node_values_exp1_1s.svg")
plt.close()
