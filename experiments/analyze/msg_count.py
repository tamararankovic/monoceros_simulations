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
    df.index = (df.index - min_ts).astype(int)
    return df

# def get_full_index(dfs: list[pd.DataFrame]) -> list[any]:
#     return sorted(set().union(*(df.index for df in dfs)))

# def reindex(df: pd.DataFrame, index: list[any]) -> pd.DataFrame:
#     df = df.reindex(index).ffill()
#     cutoff = df.attrs.get("killed", 999999999)
#     df.loc[df.index >= cutoff, ["sent", "rcvd"]] = pd.NA
#     return df

def average_nodes(rep_dir: Path, min_ts: int, max_ts: int, events: list[dict]) -> pd.DataFrame:
    node_dfs = []
    for node_dir in rep_dir.glob("r*_node_*"):
        csv_file = node_dir / "results" / "msg_count.csv"
        if csv_file.exists():
            node_df = load_node_csv(csv_file)
            # --- Apply event cutoffs ---
            for ev in events:
                cutoff = round(ev["timestamp_ns"] / 1_000_000_000 - min_ts)
                for killed in ev.get("killed", []):
                    # crude match: container name inside node_dir
                    if killed == node_dir.name:
                        node_df.loc[node_df.index >= cutoff, ["sent", "rcvd"]] = pd.NA
                        node_df.attrs["killed"] = cutoff
            node_dfs.append(node_df)
    if not node_dfs:
        raise ValueError(f"No node CSVs found in {rep_dir}")
    node_dfs = [normalize_index(df, min_ts=min_ts, max_ts=max_ts) for df in node_dfs]
    # node_dfs = [reindex(df, get_full_index(node_dfs)) for df in node_dfs]
    combined = pd.concat(node_dfs)
    averaged = combined.groupby(combined.index).mean()
    return averaged

def average_repetitions(exp_dir: Path) -> pd.DataFrame:
    rep_dfs = []
    for rep_dir in exp_dir.glob("exp_*"):
        metadata_file = rep_dir / "metadata.json"
        with metadata_file.open() as f:
            metadata = json.load(f)
        events = metadata["event_data"]["events"]
        event_ts_min = metadata["event_data"]["events"][0]["timestamp_ns"] / 1_000_000_000
        event_ts_max = metadata["event_data"]["events"][-1]["timestamp_ns"] / 1_000_000_000
        event_wait = metadata["plan"]["event_wait"]
        end_wait = metadata["plan"]["end_wait"]
        min_ts = int(round(event_ts_min - event_wait))
        max_ts = int(round(event_ts_max + end_wait))
        rep_avg = average_nodes(rep_dir, min_ts, max_ts, events)
        # if rep_avg.empty:
        #     print(f"Warning: repetition {rep_dir} has no valid data. Skipping.")
        #     continue
        rep_avg[["sent", "rcvd"]] = rep_avg[["sent", "rcvd"]] - rep_avg[["sent", "rcvd"]].iloc[0]
        rep_dfs.append(rep_avg)
    # rep_dfs = [reindex(df, get_full_index(rep_dfs)) for df in rep_dfs]
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
    # final_avg.index = final_avg.index.astype(int)
    
    print(f"Final averaged results for experiment '{experiment_name}':")
    print(final_avg)
    
    # Optionally save to CSV
    output_file = results_dir / experiment_name / f"msg_count.csv"
    final_avg.to_csv(output_file)
    print(f"Averaged results saved to {output_file}")

if __name__ == "__main__":    
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <experiment_name>")
        sys.exit(1)
    
    experiment_name = sys.argv[1]
    results_dir = Path(__file__).parent.parent / "results"
    
    main(experiment_name, results_dir)