
from pathlib import Path
import pandas as pd

# 1. Dataset folder
DATA_DIR = Path("data/bidmc/numerics")

# 2. Expected columns
EXPECTED_COLUMNS = [
    "Time [s]",
    "HR",
    "PULSE",
    "RESP",
    "SpO2"
]

MEASUREMENTS = ["HR", "PULSE", "RESP", "SpO2"]

# 3. Find all CSV files
files = sorted(DATA_DIR.glob("*_Numerics.csv"))

print(f"Found {len(files)} files")

if len(files) == 0:
    raise SystemExit("No CSV files found. Check the folder path.")

records = []
all_data = []

# 4. Inspect each recording
for file in files:

    print(f"Inspecting: {file.name}")

    df = pd.read_csv(file)
    df.columns = df.columns.str.strip()

    missing_columns = [
        col for col in EXPECTED_COLUMNS
        if col not in df.columns
    ]

    if missing_columns:
        print(f"Skipped! Missing columns: {missing_columns}")
        continue

    # Convert columns to numeric values
    for col in EXPECTED_COLUMNS:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Basic information
    record = {
        "file": file.name,
        "rows": len(df),
        "duration_seconds": (
            df["Time [s]"].max() - df["Time [s]"].min()
        ),
        "duplicate_timestamps": (
            df["Time [s]"].duplicated().sum()
        )
    }

    # Statistics for each measurement
    for col in MEASUREMENTS:

        record[f"{col}_missing"] = df[col].isna().sum()

        record[f"{col}_missing_percent"] = round(
            df[col].isna().mean() * 100, 2
        )

        record[f"{col}_mean"] = round(
            df[col].mean(), 2
        )

        record[f"{col}_min"] = df[col].min()
        record[f"{col}_max"] = df[col].max()

    records.append(record)

    df["recording"] = file.stem
    all_data.append(df)

# 5. Save inspection report
if records:

    report = pd.DataFrame(records)

    report.to_csv(
        "bidmc_inspection_report.csv",
        index=False
    )

    print("\nInspection Report Summary")
    print("-------------------------")
    print(report.to_string(index=False))

    # 6. Combine all recordings
    combined = pd.concat(all_data, ignore_index=True)

    combined.to_csv(
        "bidmc_combined_numerics.csv",
        index=False
    )

    print("\nTotal valid recordings:", len(records))
    print("Total rows:", len(combined))

    print("\nMissing values:")
    print(combined[MEASUREMENTS].isna().sum())

    print("\nFiles saved successfully!")

else:
    print("No valid recordings found.")
