import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]

# Load CSV
df = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name}/msg_count.csv")
df.set_index("timestamp", inplace=True)

# --- Plot counts ---
plt.figure(figsize=(10, 6))
plt.plot(df.index, df["sent"], label="Sent")
plt.plot(df.index, df["rcvd"], label="Received")
plt.xlabel("Time (s)")
plt.ylabel("Messages")
plt.title("Messages Sent/Received Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(f"/home/tamara/experiments/results/{experiment_name}/msg_count.svg")
plt.close()

# --- Plot rates ---
plt.figure(figsize=(10, 6))
plt.plot(df.index, df["sent_rate"], label="Sent Rate")
plt.plot(df.index, df["rcvd_rate"], label="Received Rate")
plt.xlabel("Time (s)")
plt.ylabel("Messages per Second")
plt.title("Message Rates Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(f"/home/tamara/experiments/results/{experiment_name}/msg_rate.svg")
plt.close()