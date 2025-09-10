import pandas as pd
import matplotlib.pyplot as plt
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]
BASE_DIR = Path("/home/tamara/experiments/results")

def load_msg_df(exp_name: str) -> pd.DataFrame:
    df = pd.read_csv(BASE_DIR / exp_name / "msg_count.csv")
    df.set_index("timestamp", inplace=True)
    return df

# Load both experiments
fu_df = load_msg_df(f"fu_{experiment_name}")
mc_df = load_msg_df(f"mc_{experiment_name}")

# --- Plot counts ---
plt.figure(figsize=(10, 6))
plt.plot(fu_df.index, fu_df["sent"], label="Flow Updating - Sent")
plt.plot(fu_df.index, fu_df["rcvd"], label="Flow Updating - Received")
plt.plot(mc_df.index, mc_df["sent"], label="Monoceros - Sent", linestyle="--")
plt.plot(mc_df.index, mc_df["rcvd"], label="Monoceros - Received", linestyle="--")
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
plt.plot(fu_df.index, fu_df["sent_rate"], label="Flow Updating - Sent Rate")
plt.plot(fu_df.index, fu_df["rcvd_rate"], label="Flow Updating - Received Rate")
plt.plot(mc_df.index, mc_df["sent_rate"], label="Monoceros - Sent Rate", linestyle="--")
plt.plot(mc_df.index, mc_df["rcvd_rate"], label="Monoceros - Received Rate", linestyle="--")
plt.xlabel("Time (s)")
plt.ylabel("Messages per Second")
plt.title("Message Rates Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(BASE_DIR / f"{experiment_name}_msg_rate.svg")
plt.close()
