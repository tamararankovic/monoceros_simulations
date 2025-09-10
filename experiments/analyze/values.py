import pandas as pd
from pathlib import Path
import json
import sys
from typing import Tuple

pd.set_option('display.float_format', '{:.0f}'.format)

def load_node_csv(node_csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(node_csv_path, header=None, names=["from", "ts_sent", "ts_rcvd", "value"])
    df = df.drop(columns=["from"])
    df = df.drop(columns=["ts_sent"])
    df = df.set_index("ts_rcvd").sort_index()
    df.index = df.index / 1_000_000
    df = df[~df.index.duplicated(keep='last')]
    df.attrs["tmp_path"] = node_csv_path
    return df

def normalize_index(df: pd.DataFrame, min_ts: int, max_ts: int) -> pd.DataFrame:
    df = df.loc[(df.index >= min_ts) & (df.index <= max_ts)]
    df.index = df.index - min_ts
    # df.index = df.index / 1_000_000
    return df

def get_full_index(dfs: list[pd.DataFrame]) -> list[any]:
    return sorted(set().union(*(df.index for df in dfs)))

def reindex(df: pd.DataFrame, index: list[any]) -> pd.DataFrame:
    return df.reindex(index).ffill()

def average_nodes(rep_dir: Path, exp_name, min_ts, max_ts) -> pd.DataFrame:
    node_dfs = []
    for node_dir in rep_dir.glob("r*_node_*"):
        if exp_name.startswith("mc_"):
            file_name = "avg_app_memory_usage_bytes{ func=avg level=region regionID=r1 }.csv"
        else:
            file_name = "value.csv"
        csv_file = node_dir / "results" / file_name
        if csv_file.exists():
            node_df = load_node_csv(csv_file)
            node_df.attrs["node_id"] = node_dir.name
            node_dfs.append(node_df)
    if not node_dfs:
        raise ValueError(f"No node CSVs found in {rep_dir}")
    node_dfs = [normalize_index(df, min_ts=min_ts, max_ts=max_ts) for df in node_dfs]
    node_dfs = [reindex(df, get_full_index(node_dfs)) for df in node_dfs]
    for node_df in node_dfs:
        output_file = rep_dir / node_df.attrs['node_id'] / "normalized_values.csv"
        node_df.to_csv(output_file)
    combined = pd.concat(node_dfs)
    averaged = combined.groupby(combined.index).mean()
    return averaged

# def average_repetitions(exp_dir: Path) -> Tuple[pd.DataFrame, pd.DataFrame]:
#     rep_dfs = []
#     event_ts_normalized = 0
#     expected_before = 0
#     expected_after = 0
#     for rep_dir in exp_dir.glob("exp_*"):
#         metadata_file = rep_dir / "metadata.json"
#         with metadata_file.open() as f:
#             metadata = json.load(f)
#         event_ts = metadata["event_data"]["timestamp_ns"] / 1_000_000
#         event_wait = int(metadata["plan"]["event_wait"])
#         end_wait = int(metadata["plan"]["end_wait"])
#         min_ts = event_ts - (event_wait * 1_000)
#         max_ts = event_ts + (end_wait * 1_000)
#         print(rep_dir.name)
#         print(max_ts)
#         event_ts_normalized = event_wait * 1_000
#         expected_before = metadata["event_data"]["expected_before"]
#         expected_after = metadata["event_data"]["expected_after"]
#         rep_avg = average_nodes(rep_dir, min_ts, max_ts)
#         rep_dfs.append(rep_avg)
#     # Align repetitions by index and average
#     rep_dfs = [reindex(df, get_full_index(rep_dfs)) for df in rep_dfs]
#     combined = pd.concat(rep_dfs)
#     averaged = combined.groupby(combined.index).mean()
#     expected_df = pd.DataFrame({
#         "ts_rcvd": [0, event_ts_normalized],
#         "value": [expected_before, expected_after]
#     }).set_index("ts_rcvd")
#     full_index = get_full_index([averaged] + [expected_df])
#     averaged = reindex(averaged, full_index)
#     expected_df = reindex(expected_df, full_index)
#     return averaged, expected_df

def average_repetitions(exp_dir: Path, exp_name) -> Tuple[pd.DataFrame, pd.DataFrame]:
    rep_dfs = []
    expected_dfs = []

    for rep_dir in exp_dir.glob("exp_*"):
        metadata_file = rep_dir / "metadata.json"
        with metadata_file.open() as f:
            metadata = json.load(f)

        event_data = metadata["event_data"]
        events = event_data["events"]

        event_wait = int(metadata["plan"]["event_wait"])
        end_wait = int(metadata["plan"]["end_wait"])

        # We normalize relative to the *first event timestamp*
        first_ts = events[0]["timestamp_ns"] / 1_000_000
        last_ts = events[-1]["timestamp_ns"] / 1_000_000
        min_ts = first_ts - (event_wait * 1_000)
        max_ts = last_ts + (end_wait * 1_000)

        print(rep_dir.name)
        print(max_ts)

        rep_avg = average_nodes(rep_dir, exp_name, min_ts, max_ts)
        rep_dfs.append(rep_avg)

        # --- Build expected_df for this repetition ---
        expected_records = []
        # Before event: at t=0
        expected_records.append({"ts_rcvd": 0, "value": event_data["expected_before"]})
        # Each event
        for ev in events:
            ts_norm = (ev["timestamp_ns"] / 1_000_000) - min_ts
            expected_records.append({"ts_rcvd": ts_norm, "value": ev["expected"]})

        expected_df = pd.DataFrame(expected_records).set_index("ts_rcvd").sort_index()
        expected_df.attrs["rep_id"] = rep_dir.name
        expected_dfs.append(expected_df)

    # Align repetitions by index and average
    rep_dfs = [reindex(df, get_full_index(rep_dfs)) for df in rep_dfs]
    combined = pd.concat(rep_dfs)
    averaged = combined.groupby(combined.index).mean()

    # Merge all expected_dfs
    full_index = get_full_index([averaged] + expected_dfs)
    averaged = reindex(averaged, full_index)
    expected_dfs = [reindex(df, full_index) for df in expected_dfs]
    for df in expected_dfs:
        output_file = exp_dir / df.attrs["rep_id"] / "normalized_expected_values.csv"
        df.to_csv(output_file)
    expected_all = pd.concat(expected_dfs).groupby(level=0).mean()

    return averaged, expected_all


def main(experiment_name: str, results_dir: Path):
    exp_dir = results_dir / experiment_name
    if not exp_dir.exists():
        raise ValueError(f"Experiment directory {exp_dir} does not exist")
    
    # Average by repetition
    final_avg, expected = average_repetitions(exp_dir, experiment_name)
    
    print(f"Final averaged results for experiment '{experiment_name}':")
    print(final_avg)

    print(f"Expected results for experiment '{experiment_name}':")
    print(expected)
    
    # Optionally save to CSV
    output_file = results_dir / experiment_name / f"value_measured.csv"
    final_avg.to_csv(output_file)
    print(f"Averaged results saved to {output_file}")
    output_file = results_dir / experiment_name / f"value_expected.csv"
    expected.to_csv(output_file)
    print(f"Expected results saved to {output_file}")

if __name__ == "__main__":    
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <experiment_name>")
        sys.exit(1)
    
    experiment_name = sys.argv[1]
    results_dir = Path(__file__).parent.parent / "results"
    
    main(experiment_name, results_dir)
