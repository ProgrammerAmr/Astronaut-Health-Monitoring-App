
from pathlib import Path
import pandas as pd

DATA_DIR = Path("data/bidmc/processed/numerics")
OUTPUT_DIR = Path("data/bidmc/processed")

SIGNALS = ["HR", "PULSE", "RESP", "SpO2"]

all_features = []

for file in sorted(DATA_DIR.glob("*_Numerics.csv")):

    df = pd.read_csv(file)

    features = {
        "recording_id": file.stem.replace("_Numerics", "")
    }

    for signal in SIGNALS:

        values = pd.to_numeric(
            df[signal], errors="coerce"
        ).dropna()

        features[f"{signal}_valid_count"] = len(values)
        features[f"{signal}_missing_count"] = (
            len(df) - len(values)
        )

        if len(values) > 0:
            features[f"{signal}_mean"] = values.mean()
            features[f"{signal}_median"] = values.median()
            features[f"{signal}_min"] = values.min()
            features[f"{signal}_max"] = values.max()
            features[f"{signal}_std"] = values.std()
        else:
            features[f"{signal}_mean"] = None
            features[f"{signal}_median"] = None
            features[f"{signal}_min"] = None
            features[f"{signal}_max"] = None
            features[f"{signal}_std"] = None

    all_features.append(features)

features_df = pd.DataFrame(all_features)

output_file = OUTPUT_DIR / "bidmc_features.csv"
features_df.to_csv(output_file, index=False)

print("FEATURE EXTRACTION COMPLETED")
print("============================")
print("Total recordings:", len(features_df))
print("Features per recording:", len(features_df.columns) - 1)
print("Saved to:", output_file)

print("\nFirst 5 recordings:")
print(features_df.head().to_string(index=False))
