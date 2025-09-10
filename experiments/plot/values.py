import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <experiment_name>")
    sys.exit(1)

experiment_name = sys.argv[1]

# Load CSV
df_1 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name}/value_measured.csv")
df_1.set_index("ts_rcvd", inplace=True)

df_2 = pd.read_csv(f"/home/tamara/experiments/results/{experiment_name}/value_expected.csv")
df_2.set_index("ts_rcvd", inplace=True)

# Convert index from milliseconds → seconds
df_1.index = df_1.index / 1000.0
df_2.index = df_2.index / 1000.0

# --- Plot values ---
plt.figure(figsize=(10, 6))
plt.plot(df_1.index, df_1["value"], label="Measured")
plt.plot(df_2.index, df_2["value"], label="Expected")
plt.xlabel("Time (s)")
plt.ylabel("Value")
plt.title("Measured VS expected value")
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.savefig(f"/home/tamara/experiments/results/{experiment_name}/value.svg")
plt.close()