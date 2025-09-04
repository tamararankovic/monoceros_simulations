import sys
import pandas as pd
import matplotlib.pyplot as plt

def load_csv(path: str, column_names: list[str], x_col: str) -> pd.DataFrame:
    df = pd.read_csv(path, header=None, names=column_names)
    df = df.set_index(x_col)
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

def save_plot(
    dfs: list[pd.DataFrame],
    labels: list[str],
    scatter: list[bool],
    value_col: str,
    title: str,
    xlabel: str,
    ylabel: str,
    output_file: str,
    figsize: tuple = (8, 5),
):
    plt.figure(figsize=figsize)

    n = len(dfs)
    markers = ['o', 'x', 's', '^', 'd', '*', '+', 'v', '<', '>'] * ((n // 10) + 1)
    for i, df in enumerate(dfs):
        x = df.index
        if scatter[i]:
            plt.scatter(x, df[value_col], marker=markers[i], label=labels[i], c="red")
        else:
            plt.plot(x, df[value_col], marker=markers[i], label=labels[i])
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend(loc=0)
    plt.xticks(ticks=range(0, dfs[0].index.max()+1, 1))
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(output_file)
    plt.close()




if len(sys.argv) < 3:
    print("min and max ts must be set")
    exit(1)

min_ts = int(sys.argv[1])
max_ts = int(sys.argv[2])

if min_ts < 0 or max_ts < 0 or min_ts > max_ts:
    print("timestamps invalid")
    exit(1)

print("min timestamp", min_ts)
print("max timestamp", max_ts)

column_names = ["timestamp", "value", "value2"]
x_col = "timestamp"

dfs = []
dfs.append(load_csv("ts1.csv", column_names=column_names, x_col=x_col))
dfs.append(load_csv("ts2.csv", column_names=column_names, x_col=x_col))
target = load_csv("target.csv", column_names=column_names, x_col=x_col)

dfs = [normalize_index(df, min_ts=min_ts, max_ts=max_ts) for df in dfs]
target = normalize_index(target, min_ts=min_ts, max_ts=max_ts)
index_full = get_full_index(dfs + [target])
dfs = [reindex(df, index_full) for df in dfs]
target = reindex(target, index_full)

for df in dfs:
    print(df)

print(target)

combined = pd.concat(dfs)
avg_df = combined.groupby(combined.index).mean()
print(avg_df)

# avg real vs target
save_plot(dfs=[avg_df, target], 
          labels=["real", "expected"],
          scatter=[False, False],
          value_col="value", 
          title="Values over time",
          xlabel="time",
          ylabel="value",
          output_file="plot1.svg")

# target and real distribution
save_plot(dfs=[combined, target], 
          labels=["real", "expected"],
          scatter=[True, False],
          value_col="value", 
          title="Values over time",
          xlabel="time",
          ylabel="value",
          output_file="plot2.svg")