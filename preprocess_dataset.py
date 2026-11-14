
from pathlib import Path
import pandas as pd
import numpy as np

SOURCE_DIR = Path("data/bidmc/numerics")
OUTPUT_DIR = Path("data/bidmc/processed/numerics")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SIGNALS = ["HR", "PULSE", "RESP", "SpO2"]
MAX_GAP = 5

summary = []

print("DATA PREPROCESSING")
print("==================")

for file in sorted(SOURCE_DIR.glob("*_Numerics.csv")):

    df = pd.read_csv(file)
    df.columns = df.columns.str.strip()

    report = {
        "file": file.name
    }

    # Convert signal columns to numeric
    for col in SIGNALS:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Treat RESP zeros in record 13 as unavailable values
    if file.name == "bidmc_13_Numerics.csv":
        zero_count = int((df["RESP"] == 0).sum())
        df["RESP"] = df["RESP"].replace(0, np.nan)
        print(f"Record 13: converted {zero_count} RESP zeros to NaN")

    # Record missing values before processing
    for col in SIGNALS:
        report[f"{col}_missing_before"] = int(df[col].isna().sum())

    # Fill only short internal gaps (up to 5 consecutive rows)
    for col in SIGNALS:

        values = df[col].copy()
        missing = values.isna()

        groups = (missing != missing.shift()).cumsum()

        for _, group in df[missing].groupby(groups[missing]):

            start = group.index.min()
            end = group.index.max()
            gap_length = len(group)

            # Do not fill gaps at the beginning or end
            if (
                gap_length <= MAX_GAP
                and start > 0
                and end < len(df) - 1
            ):
                previous_value = values.loc[start - 1]
                next_value = values.loc[end + 1]

                if pd.notna(previous_value) and pd.notna(next_value):

                    positions = np.arange(start, end + 1)

                    interpolated = np.interp(
                        positions,
                        [start - 1, end + 1],
                        [previous_value, next_value]
                    )

                    df.loc[positions, col] = interpolated

        report[f"{col}_missing_after"] = int(df[col].isna().sum())

    # Save processed recording
    output_file = OUTPUT_DIR / file.name
    df.to_csv(output_file, index=False)

    summary.append(report)

    print(f"Processed: {file.name}")

# Save processing summary
summary_df = pd.DataFrame(summary)

summary_file = OUTPUT_DIR.parent / "preprocessing_summary.csv"
summary_df.to_csv(summary_file, index=False)

print("\n==================")
print("PREPROCESSING COMPLETED")
print("Processed recordings:", len(summary))
print("Output folder:", OUTPUT_DIR)
print("Summary:", summary_file)
