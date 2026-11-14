
from pathlib import Path
import pandas as pd

file = Path("data/bidmc/numerics/bidmc_13_Numerics.csv")

df = pd.read_csv(file)
df.columns = df.columns.str.strip()

resp = pd.to_numeric(df["RESP"], errors="coerce")
zero_mask = resp.eq(0)

groups = (zero_mask != zero_mask.shift()).cumsum()

print("RECORD 13 - RESP ZERO INSPECTION")
print("================================")
print("Total zero values:", int(zero_mask.sum()))

for _, group in df[zero_mask].groupby(groups[zero_mask]):
    start = group.index.min()
    end = group.index.max()

    print(f"\nZero range: {df.loc[start, 'Time [s]']}s "
          f"to {df.loc[end, 'Time [s]']}s")
    print("Number of zeros:", len(group))

    print("Values around this range:")

    before = max(0, start - 2)
    after = min(len(df) - 1, end + 2)

    print(df.loc[before:after, ["Time [s]", "RESP"]].to_string(index=False))

print("\nNon-zero RESP statistics:")
print(resp[resp != 0].describe())
