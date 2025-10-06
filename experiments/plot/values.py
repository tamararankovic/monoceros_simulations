import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]

# Load CSV
df_1 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name}/value_measured.csv")
df_2 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name}/value_expected.csv")

# Convert index from milliseconds → seconds
# df_1["ts_rcvd"] = df_1["ts_rcvd"] / 1000.0
# df_2["ts_rcvd"] = df_2["ts_rcvd"] / 1000.0

# Set index
df_1.set_index("ts_rcvd", inplace=True)
df_2.set_index("ts_rcvd", inplace=True)

# Round timestamps to avoid tiny float differences
df_1.index = df_1.index.round(3)
df_2.index = df_2.index.round(3)
df_1["value"] = df_1["value"].round(4)
df_2["value"] = df_2["value"].round(4)

# Aggregate in case of duplicates
df_1 = df_1.groupby(df_1.index).mean()
df_2 = df_2.groupby(df_2.index).mean()

# --- Plot values ---
plt.figure(figsize=(10, 6))
plt.plot(df_1.index, df_1["value"], label="Measured")
plt.plot(df_2.index, df_2["value"], label="Expected")
plt.ticklabel_format(useOffset=False, style='plain', axis='y')
plt.xlabel("Time (s)")
plt.ylabel("Value")
plt.title("Measured VS Expected Value")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(f"/home/tamara/experiments/results/{experiment_name}/value.svg")
plt.close()
