# External Dataset Reference: NASA Flight Crew Physiological Data for Crew State Monitoring

> **Governance Rule (`docs/DATA_AND_DELIVERABLES.md` §5):** Do **NOT** commit downloaded `.zip` or `.csv` files from this dataset to GitHub. Keep all raw downloads inside `data/external/nasa_csm/raw/` (ignored by `.gitignore`).

## 1. Provenance Metadata (Verified from NASA Open Data Portal CKAN API)

| Field | Verified Value |
|---|---|
| **Dataset Name** | Flight Crew Physiological Data for Crew State Monitoring |
| **Landing Page** | https://data.nasa.gov/dataset/flight-crew-physiological-data-for-crew-state-monitoring |
| **CKAN API Endpoint** | https://data.nasa.gov/api/3/action/package_show?id=flight-crew-physiological-data-for-crew-state-monitoring |
| **Package ID** | `7f671252-e746-407d-b255-83dc743a8df5` |
| **Legacy Identifier** | `https://data.nasa.gov/api/views/8a5d-xhfr` |
| **Maintainer / Publisher** | Dr. Angela R. Harrivel (`angela.r.harrivel@nasa.gov`), NASA Langley Research Center |
| **Issued / Modified** | Issued `2019-09-17`; Source Modified `2024-05-15`; Portal Updated `2025-04-23` |
| **Access Level** | `public` (`private: false`) |
| **License Status** | **`License not specified`** (`license_id: "notspecified"`, `isopen: false`) — verify redistribution terms before any sharing |
| **Sampling Rate** | 256 Hz across 20 EEG (B-Alert X24) + ECG, R, GSR (NeXus-10 Mark II) |
| **Published Resources** | **17 subject ZIPs** (`5, 6, 9, 10, 11, 12, 13, 14, 17, 18, 19, 21, 22, 23, 24, 25, 26`) + `description.txt` (**Subject `20.zip` is absent from the catalog** despite `description.txt` stating 18 pilots) |

## 2. Official Resource URLs

- Description: `https://data.nasa.gov/docs/datasets/public/csm/description.txt`
- Subject Archives (17 listed):
  - Crew 3: `5.zip`, `6.zip`
  - Crew 5: `9.zip`, `10.zip`
  - Crew 6: `11.zip`, `12.zip`
  - Crew 7: `13.zip`, `14.zip`
  - Crew 9: `17.zip`, `18.zip`
  - Crew 10: `19.zip` *(Note: `20.zip` missing from portal listing)*
  - Crew 11: `21.zip`, `22.zip`
  - Crew 12: `23.zip`, `24.zip`
  - Crew 13: `25.zip`, `26.zip`
- Base URL pattern: `https://data.nasa.gov/docs/datasets/public/csm/<subject_id>.zip`

## 3. Running the Mandatory Stop-Condition #1 Local Raw-Data Audit

From the repository root on a machine with unrestricted internet access to `data.nasa.gov`:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r AI_training/csm/requirements-csm.txt

PYTHONPATH=AI_training python -m csm.audit_raw_data \
  --download \
  --check-missing-20 \
  --data-dir data/external/nasa_csm/raw \
  --out-dir audit_outputs/nasa_csm
```

This generates:
- `audit_outputs/nasa_csm/audit_report.md` (human-readable Stop-Condition gate summary)
- `audit_outputs/nasa_csm/audit_report.json` (full machine-readable statistics & checksums)
- `audit_outputs/nasa_csm/audit_summary_files.csv` (per-file schema, NaNs, gaps, GSR zero-dropouts, saturation, signal ranges)
- `audit_outputs/nasa_csm/audit_class_distribution.csv` (per-pilot × session `Event` counts, stray `3`/`4` counts, and contiguous episode counts)
