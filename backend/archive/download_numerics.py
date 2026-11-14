
from pathlib import Path
from urllib.request import urlretrieve

# Destination folder
DATA_DIR = Path("data/bidmc/numerics")
DATA_DIR.mkdir(parents=True, exist_ok=True)

BASE_URL = "https://physionet.org/files/bidmc/1.0.0/bidmc_csv/"

# Download all 53 Numerics files
for i in range(1, 54):

    filename = f"bidmc_{i:02d}_Numerics.csv"
    file_path = DATA_DIR / filename
    file_url = BASE_URL + filename

    # Skip existing files
    if file_path.exists() and file_path.stat().st_size > 0:
        print(f"Already exists: {filename}")
        continue

    try:
        print(f"Downloading {filename}...")

        urlretrieve(file_url, file_path)

        print(f"Downloaded successfully: {filename}")

    except Exception as error:
        print(f"Failed: {filename}")
        print(error)

print("\nDownload process finished!")

# Count downloaded files
files = list(DATA_DIR.glob("*_Numerics.csv"))
print(f"Total files available: {len(files)}")
