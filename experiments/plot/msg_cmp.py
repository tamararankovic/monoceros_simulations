import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) != 3:
    print(f"Usage: python {sys.argv[0]} <experiment_name_1> <experiment_name_2>")
    sys.exit(1)

experiment_name_1 = sys.argv[1]
experiment_name_2 = sys.argv[2]

# Load CSV
df_1 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name_1}/msgs_averaged.csv")
df_1.set_index("timestamp", inplace=True)

df_2 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name_2}/msgs_averaged.csv")
df_2.set_index("timestamp", inplace=True)

# --- Plot counts ---
plt.figure(figsize=(10, 6))
plt.plot(df_1.index, df_1["sent"], label="Sent")
plt.plot(df_1.index, df_1["rcvd"], label="Received")
plt.plot(df_2.index, df_2["sent"], label="Sent (Neighborhood scored known)")
plt.plot(df_2.index, df_2["rcvd"], label="Received (Neighborhood scored known)")
plt.xlabel("Time (s)")
plt.ylabel("Messages")
plt.title("Messages Sent/Received Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig("msg_count_cmp.svg")
plt.close()

# --- Plot rates ---
plt.figure(figsize=(10, 6))
plt.plot(df_1.index, df_1["sent_rate"], label="Sent Rate")
plt.plot(df_1.index, df_1["rcvd_rate"], label="Received Rate")
plt.plot(df_2.index, df_2["sent_rate"], label="Sent Rate (Neighborhood scored known)")
plt.plot(df_2.index, df_2["rcvd_rate"], label="Received Rate (Neighborhood scored known)")
plt.xlabel("Time (s)")
plt.ylabel("Messages per Second")
plt.title("Message Rates Over Time")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig("msg_rate_cmp.svg")
plt.close()
