import pandas as pd
from pathlib import Path
import json
import sys
from typing import Tuple

def load_node_csv(node_csv_path: Path) -> pd.DataFrame:
    """Load a CSV for a single node, indexed by timestamp."""
    df = pd.read_csv(node_csv_path, header=None, names=["from", "ts_sent", "ts_rcvd", "value"])
    df = df.drop(columns=["from"])
    df = df.drop(columns=["ts_sent"])
    df = df.set_index("ts_rcvd").sort_index()
    df.index = df.index / 1_000_000
    df = df[~df.index.duplicated(keep='last')]
    return df

def normalize_index(df: pd.DataFrame, min_ts: int, max_ts: int) -> pd.DataFrame:
    df = df.loc[(df.index >= min_ts) & (df.index <= max_ts)]
    df.index = df.index - df.index.min()
    return df

def get_full_index(dfs: list[pd.DataFrame]) -> list[any]:
    return sorted(set().union(*(df.index for df in dfs)))

def reindex(df: pd.DataFrame, index: list[any]) -> pd.DataFrame:
    return df.reindex(index).ffill()

def average_nodes(rep_dir: Path, min_ts, max_ts) -> pd.DataFrame:
    node_dfs = []
    for node_dir in rep_dir.glob("r*_node_*"):
        csv_file = node_dir / "results" / "total_app_memory_usage_bytes{ global=y level=global }.csv"
        if csv_file.exists():
            node_dfs.append(load_node_csv(csv_file))
    if not node_dfs:
        raise ValueError(f"No node CSVs found in {rep_dir}")
    node_dfs = [normalize_index(df, min_ts=min_ts, max_ts=max_ts) for df in node_dfs]
    node_dfs = [reindex(df, get_full_index(node_dfs)) for df in node_dfs]
    combined = pd.concat(node_dfs)
    averaged = combined.groupby(combined.index).mean()
    return averaged

def average_repetitions(exp_dir: Path) -> Tuple[pd.DataFrame, pd.DataFrame]:
    rep_dfs = []
    event_ts_normalized = 0
    expected_before = 0
    expected_after = 0
    for rep_dir in exp_dir.glob("exp_*"):
        metadata_file = rep_dir / "metadata.json"
        with metadata_file.open() as f:
            metadata = json.load(f)
        event_ts = metadata["event_data"]["timestamp_ns"] / 1_000_000
        event_wait = int(metadata["plan"]["event_wait"])
        end_wait = int(metadata["plan"]["end_wait"])
        min_ts = event_ts - (event_wait * 1_000)
        max_ts = event_ts + (end_wait * 1_000)
        event_ts_normalized = event_wait * 1_000
        expected_before = metadata["event_data"]["expected_before"]
        expected_after = metadata["event_data"]["expected_after"]
        rep_avg = average_nodes(rep_dir, min_ts, max_ts)
        rep_dfs.append(rep_avg)
    # Align repetitions by index and average
    rep_dfs = [reindex(df, get_full_index(rep_dfs)) for df in rep_dfs]
    combined = pd.concat(rep_dfs)
    averaged = combined.groupby(combined.index).mean()
    expected_df = pd.DataFrame({
        "ts_rcvs": [0, event_ts_normalized],
        "value": [expected_before, expected_after]
    }).set_index("ts_rcvs")
    full_index = get_full_index([averaged] + [expected_df])
    averaged = reindex(averaged, full_index)
    expected_df = reindex(expected_df, full_index)
    return averaged, expected_df

def main(experiment_name: str, results_dir: Path):
    exp_dir = results_dir / experiment_name
    if not exp_dir.exists():
        raise ValueError(f"Experiment directory {exp_dir} does not exist")
    
    # Average by repetition
    final_avg, expected = average_repetitions(exp_dir)
    
    print(f"Final averaged results for experiment '{experiment_name}':")
    print(final_avg)

    print(f"Expected results for experiment '{experiment_name}':")
    print(expected)
    
    # Optionally save to CSV
    output_file = results_dir / experiment_name / f"{experiment_name}_averaged.csv"
    final_avg.to_csv(output_file)
    print(f"Averaged results saved to {output_file}")
    output_file = results_dir / experiment_name / f"expected.csv"
    expected.to_csv(output_file)
    print(f"Expected results saved to {output_file}")

if __name__ == "__main__":    
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <experiment_name>")
        sys.exit(1)
    
    experiment_name = sys.argv[1]
    results_dir = Path(__file__).parent.parent / "results"
    
    main(experiment_name, results_dir)
