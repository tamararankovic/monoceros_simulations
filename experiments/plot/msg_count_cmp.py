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

def load_msg_df(exp_name: str) -> pd.DataFrame:
    df = pd.read_csv(BASE_DIR / exp_name / "msg_count.csv")
    df.set_index("timestamp", inplace=True)
    return df

# --- Load data for all prefixes ---
msg_data = {}
for prefix in prefixes:
    exp_dir_name = f"{prefix}_{experiment_name}"
    msg_data[prefix] = load_msg_df(exp_dir_name)

# --- Plot counts ---
plt.figure(figsize=(10, 6))
for prefix, df in msg_data.items():
    plt.plot(df.index, df["sent"], label=f"{prefix.upper()} - Sent")
    plt.plot(df.index, df["rcvd"], label=f"{prefix.upper()} - Received", linestyle="--")

plt.xlabel("Time (s)")
plt.ylabel("Messages")
plt.title("Messages Sent/Received Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_msg_count.svg")
plt.close()

# --- Plot rates ---
plt.figure(figsize=(10, 6))
for prefix, df in msg_data.items():
    plt.plot(df.index, df["sent_rate"], label=f"{prefix.upper()} - Sent Rate")
    plt.plot(df.index, df["rcvd_rate"], label=f"{prefix.upper()} - Received Rate", linestyle="--")

plt.xlabel("Time (s)")
plt.ylabel("Messages per Second")
plt.title("Message Rates Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_msg_rate.svg")
plt.close()
