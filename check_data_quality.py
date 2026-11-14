
import pandas as pd

report = pd.read_csv("bidmc_inspection_report.csv")

columns = [
    "HR_missing_percent",
    "PULSE_missing_percent",
    "RESP_missing_percent",
    "SpO2_missing_percent"
]

print("\nDATA QUALITY CHECK")
print("==================")

print("\nTotal recordings:", len(report))

print("\nRecordings with missing values:")
problematic = report[report[columns].gt(0).any(axis=1)]

print(
    problematic[
        ["file"] + columns
    ].to_string(index=False)
)

print("\nTotal missing values per signal:")
for column in columns:
    signal = column.replace("_missing_percent", "")
    missing = report[f"{signal}_missing"].sum()
    print(f"{signal}: {missing}")

print("\nRecordings with more than 5% missing values:")
high_missing = report[report[columns].gt(5).any(axis=1)]

print(
    high_missing[
        ["file"] + columns
    ].to_string(index=False)
)

print("\nQuality check completed!")
