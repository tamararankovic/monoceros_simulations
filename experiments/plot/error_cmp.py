# import pandas as pd
# import numpy as np
# import matplotlib.pyplot as plt
# import sys
# from pathlib import Path

# if len(sys.argv) != 2:
#     print(f"Usage: python {sys.argv[0]} <experiment_name>")
#     sys.exit(1)

# experiment_name = sys.argv[1]
# BASE_DIR = Path("/home/tamara/experiments/results")

# def compute_percentage_error(exp_name: str, common_index: pd.Index) -> pd.Series:
#     """Compute the percentage error averaged across nodes and repetitions, aligned to a common index."""
#     exp_dir = BASE_DIR / exp_name
#     repetitions = sorted(exp_dir.glob("exp_*"))
#     all_errors = []

#     for rep_dir in repetitions:
#         expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
#         expected_df.set_index("ts_rcvd", inplace=True)
#         expected_df = expected_df.reindex(common_index).fillna(method='bfill').fillna(method='ffill')

#         node_files = sorted(rep_dir.glob("*/normalized_values.csv"))
#         node_dfs = []
#         for f in node_files:
#             node_df = pd.read_csv(f)
#             node_df.set_index("ts_rcvd", inplace=True)
#             # Align to common index, backward-fill first, forward-fill last
#             node_df = node_df.reindex(common_index).fillna(method='ffill').fillna(method='bfill')
#             node_dfs.append(node_df)

#         measured_df = pd.concat(node_dfs, axis=1).mean(axis=1).to_frame(name="value")
#         perc_error = np.abs(measured_df["value"] - expected_df["value"]) / expected_df["value"] * 100
#         all_errors.append(perc_error)

#     return pd.concat(all_errors, axis=1).mean(axis=1)


# # --- Determine common index across both experiments ---
# def get_full_index(exp_names):
#     ts_all = []
#     for exp_name in exp_names:
#         exp_dir = BASE_DIR / exp_name
#         repetitions = sorted(exp_dir.glob("exp_*"))
#         for rep_dir in repetitions:
#             expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
#             ts_all.extend(expected_df["ts_rcvd"].values)
#     return pd.Index(sorted(set(ts_all)))

# common_index = get_full_index([f"fu_{experiment_name}", f"mc_{experiment_name}"])

# # --- Compute aligned percentage errors ---
# fu_errors = compute_percentage_error(f"fu_{experiment_name}", common_index)
# mc_errors = compute_percentage_error(f"mc_{experiment_name}", common_index)

# # --- Plot ---
# plt.figure(figsize=(10,6))
# plt.plot(common_index / 1000, fu_errors.values, label="Flow Updating")
# plt.plot(common_index / 1000, mc_errors.values, label="Monoceros")
# plt.xlabel("Time (s)")
# plt.ylabel("Percentage error (%)")
# plt.title("Percentage error comparison")
# plt.legend()
# plt.grid(True)
# plt.tight_layout()
# plt.savefig(BASE_DIR / f"{experiment_name}_percentage_error.svg")
# plt.close()


#!/usr/bin/env python3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]
BASE_DIR = Path("/home/tamara/experiments/results")

prefixes = ["fu", "mc", "dd", "ep", "rr"]

def compute_rmse(exp_name: str, common_index: pd.Index) -> pd.Series:
    """
    Compute the RMSE averaged across nodes and repetitions, aligned to a common index.
    Returns a pd.Series indexed by the common_index.
    """
    exp_dir = BASE_DIR / exp_name
    repetitions = sorted(exp_dir.glob("exp_*"))
    all_squares = []

    for rep_dir in repetitions:
        expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
        expected_df.set_index("ts_rcvd", inplace=True)
        expected_df = expected_df.reindex(common_index)

        node_files = sorted(rep_dir.glob("*/normalized_values.csv"))
        node_dfs = []
        for f in node_files:
            node_df = pd.read_csv(f)
            node_df.set_index("ts_rcvd", inplace=True)
            node_df = node_df.reindex(common_index)
            node_dfs.append(node_df)

        measured_df = pd.concat(node_dfs, axis=1).mean(axis=1)
        squared_error = (measured_df - expected_df["value"]) ** 2
        all_squares.append(squared_error)

    # Average squared errors across repetitions and take sqrt
    mean_square = pd.concat(all_squares, axis=1).mean(axis=1)
    rmse = np.sqrt(mean_square)
    return rmse

# --- Determine common index across all experiments ---
def get_full_index(exp_name: str) -> pd.Index:
    ts_all = []
    for prefix in prefixes:
        exp_dir = BASE_DIR / f"{prefix}_{exp_name}"
        repetitions = sorted(exp_dir.glob("exp_*"))
        for rep_dir in repetitions:
            expected_df = pd.read_csv(rep_dir / "normalized_expected_values.csv")
            ts_all.extend(expected_df["ts_rcvd"].values)
    return pd.Index(sorted(set(ts_all)))

common_index = get_full_index(experiment_name)

# --- Compute aligned RMSE for all prefixes ---
rmse_dict = {}
for prefix in prefixes:
    exp_dir_name = f"{prefix}_{experiment_name}"
    rmse_series = compute_rmse(exp_dir_name, common_index).ffill()
    rmse_dict[prefix] = rmse_series.round(4)

# --- Plot ---
plt.figure(figsize=(10,6))
for prefix, series in rmse_dict.items():
    plt.plot(common_index, series.values, label=prefix.upper())

plt.yscale("log")
# plt.ticklabel_format(useOffset=False, style='plain', axis='y')
plt.xlabel("Time (s)")
plt.ylabel("RMSE")
plt.title("RMSE comparison")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_rmse.svg")
plt.close()
