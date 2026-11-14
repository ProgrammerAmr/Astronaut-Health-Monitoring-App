
from pathlib import Path
import pandas as pd

DATA_DIR = Path("data/bidmc/numerics")
SIGNALS = ["HR", "PULSE", "RESP", "SpO2"]

print("MISSING GAPS INSPECTION")
print("======================")

for file in sorted(DATA_DIR.glob("*_Numerics.csv")):
    df = pd.read_csv(file)
    df.columns = df.columns.str.strip()

    for col in SIGNALS:
        values = pd.to_numeric(df[col], errors="coerce")
        missing = values.isna()

        if missing.any():
            groups = (missing != missing.shift()).cumsum()

            gaps = (
                df.loc[missing]
                .groupby(groups[missing])
                .agg(
                    start_time=("Time [s]", "min"),
                    end_time=("Time [s]", "max"),
                    missing_count=("Time [s]", "count")
                )
            )

            for _, gap in gaps.iterrows():
                print(
                    f"{file.name} | {col} | "
                    f"from {gap['start_time']}s to "
                    f"{gap['end_time']}s | "
                    f"{int(gap['missing_count'])} missing"
                )

    # Check zero values separately
    for col in SIGNALS:
        values = pd.to_numeric(df[col], errors="coerce")
        zero_count = (values == 0).sum()

        if zero_count > 0:
            print(
                f"ZERO VALUES: {file.name} | "
                f"{col} | {zero_count} zeros"
            )

print("\nInspection completed!")
