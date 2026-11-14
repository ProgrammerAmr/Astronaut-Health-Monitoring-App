
from pathlib import Path
import pandas as pd
import json

INPUT_FILE = Path(
    "data/bidmc/processed/bidmc_features.csv"
)

OUTPUT_FILE = Path(
    "data/bidmc/processed/bidmc_features.json"
)

df = pd.read_csv(INPUT_FILE)

SIGNALS = ["HR", "PULSE", "RESP", "SpO2"]

recordings = []

for _, row in df.iterrows():

    signals_data = {}
    quality_notes = []

    for signal in SIGNALS:

        valid_count = int(row[f"{signal}_valid_count"])
        missing_count = int(row[f"{signal}_missing_count"])

        total = valid_count + missing_count

        coverage = (
            round(valid_count / total * 100, 2)
            if total > 0 else 0
        )

        signals_data[signal] = {
            "mean": round(float(row[f"{signal}_mean"]), 3),
            "median": float(row[f"{signal}_median"]),
            "min": float(row[f"{signal}_min"]),
            "max": float(row[f"{signal}_max"]),
            "std": round(float(row[f"{signal}_std"]), 3),
            "valid_count": valid_count,
            "missing_count": missing_count,
            "coverage_percent": coverage
        }

        if coverage < 80:
            quality_notes.append(
                f"{signal} has limited data coverage"
            )

    recordings.append({
        "recording_id": row["recording_id"],
        "source": "BIDMC PPG and Respiration Dataset",
        "duration_seconds": 480,
        "signals": signals_data,
        "data_quality": {
            "status": "limited" if quality_notes else "sufficient_for_demo",
            "notes": quality_notes
        }
    })

output_data = {
    "dataset": "BIDMC PPG and Respiration",
    "total_recordings": len(recordings),
    "quality_threshold_percent": 80,
    "usage": "Research and software prototype only. Not for medical diagnosis.",
    "recordings": recordings
}

with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
    json.dump(output_data, file, indent=4, ensure_ascii=False)

print("JSON EXPORT COMPLETED")
print("======================")
print("Total recordings:", len(recordings))
print("Output:", OUTPUT_FILE)
