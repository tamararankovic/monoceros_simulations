import pandas as pd
from pathlib import Path
import json
import sys

def load_node_csv(node_csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(node_csv_path, header=None, names=["timestamp", "sent", "rcvd"])
    df = df.set_index("timestamp").sort_index()
    df.index = (df.index / 1_000_000_000).round().astype(int)
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
        csv_file = node_dir / "results" / "msg_count.csv"
        if csv_file.exists():
            node_dfs.append(load_node_csv(csv_file))
    if not node_dfs:
        raise ValueError(f"No node CSVs found in {rep_dir}")
    node_dfs = [normalize_index(df, min_ts=min_ts, max_ts=max_ts) for df in node_dfs]
    node_dfs = [reindex(df, get_full_index(node_dfs)) for df in node_dfs]
    combined = pd.concat(node_dfs)
    averaged = combined.groupby(combined.index).mean()
    averaged.index = averaged.index
    return averaged

def average_repetitions(exp_dir: Path) -> pd.DataFrame:
    rep_dfs = []
    for rep_dir in exp_dir.glob("exp_*"):
        metadata_file = rep_dir / "metadata.json"
        with metadata_file.open() as f:
            metadata = json.load(f)
        event_ts = round(metadata["event_data"]["timestamp_ns"] / 1_000_000_000)
        event_wait = int(metadata["plan"]["event_wait"])
        end_wait = int(metadata["plan"]["end_wait"])
        min_ts = event_ts - event_wait
        max_ts = event_ts + end_wait
        rep_avg = average_nodes(rep_dir, min_ts, max_ts)
        rep_avg[["sent", "rcvd"]] = rep_avg[["sent", "rcvd"]] - rep_avg[["sent", "rcvd"]].iloc[0]
        rep_dfs.append(rep_avg)
    # Align repetitions by index and average
    rep_dfs = [reindex(df, get_full_index(rep_dfs)) for df in rep_dfs]
    combined = pd.concat(rep_dfs)
    averaged = combined.groupby(combined.index).mean()
    return averaged

def add_rates(df: pd.DataFrame) -> pd.DataFrame:
    df = df.sort_index()
    
    dt = df.index.to_series().diff()  # in seconds
    df["sent_rate"] = df["sent"].diff() / dt
    df["rcvd_rate"] = df["rcvd"].diff() / dt
    
    df = df.fillna(0)
    return df

def main(experiment_name: str, results_dir: Path):
    exp_dir = results_dir / experiment_name
    if not exp_dir.exists():
        raise ValueError(f"Experiment directory {exp_dir} does not exist")
    
    # Average by repetition
    final_avg = average_repetitions(exp_dir)
    final_avg = add_rates(final_avg)
    
    print(f"Final averaged results for experiment '{experiment_name}':")
    print(final_avg)
    
    # Optionally save to CSV
    output_file = results_dir / experiment_name / f"msgs_averaged.csv"
    final_avg.to_csv(output_file)
    print(f"Averaged results saved to {output_file}")

if __name__ == "__main__":    
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <experiment_name>")
        sys.exit(1)
    
    experiment_name = sys.argv[1]
    results_dir = Path(__file__).parent.parent / "results"
    
    main(experiment_name, results_dir)