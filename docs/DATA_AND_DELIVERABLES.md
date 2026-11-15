
# Data and Deliverables
## Astronaut Health Monitoring App

## 1. Purpose

This document defines how the project handles data, documents data sources, and organizes the expected project deliverables.

## 2. Data Strategy

The project may use:

### 2.1 Real Data
Data obtained from documented and relevant sources, such as NASA or other trusted research and space-agency datasets.

### 2.2 Simulated Data
Data created to simulate measurements and demonstrate application functionality when real data is unavailable.

### 2.3 Synthetic Data
Artificially generated data used for controlled experimentation and testing.

The team must clearly distinguish between these categories.

## 3. Data Source Documentation

Every dataset must have a documented record containing:

- Dataset name.
- Source and original URL.
- Description.
- Data collection context.
- Available features and measurements.
- Units of measurement.
- Time range, if available.
- Number of records or subjects, if known.
- Missing-data information.
- License and usage restrictions.
- Known limitations.

## 4. Data Quality and Preparation

Before using a dataset, the AI team should:

1. Inspect the dataset structure.
2. Understand the meaning of its features.
3. Check data types and units.
4. Identify missing values.
5. Check duplicates and invalid records.
6. Examine distributions and unusual values.
7. Document preprocessing decisions.
8. Avoid data leakage during model evaluation.

Any transformation applied to the data should be documented and reproducible.

## 5. Data Management Rules

- Keep original datasets unchanged whenever possible.
- Document preprocessing steps.
- Avoid committing large datasets directly to GitHub.
- Use documented download instructions or dataset links.
- Never include private or sensitive personal information unnecessarily.
- Do not mix real and simulated data without clear labeling.
- Respect dataset licenses and usage conditions.

## 6. Proposed Repository Data Structure

data/
    README.md
    raw/
    processed/
    sample/
    external/

### Directory Responsibilities

- raw/: Original downloaded datasets, when permitted.
- processed/: Prepared datasets, when permitted.
- sample/: Small samples suitable for development and testing.
- external/: References and instructions for external datasets.

Large files may be stored outside GitHub with documented access instructions.

## 7. AI / Data Science Deliverables

Expected deliverables include:

- Dataset documentation.
- Exploratory Data Analysis (EDA).
- Data preprocessing workflow.
- Baseline analytical or ML approach.
- Evaluation results, when applicable.
- Model or analysis artifact, if needed.
- Documented input/output format.
- Limitations and assumptions.

The team should avoid building a complex model unless the data and problem justify it.

## 8. Application Deliverables

### Frontend
- Working Flutter application.
- Dashboard.
- Health measurement visualizations.
- Alerts or insights interface.

### Backend
- Working API endpoints.
- Data retrieval and processing.
- AI service integration, if required.
- Error handling.

### AI / Data Science
- Reproducible analysis.
- Documented method.
- Evaluation evidence.
- Structured outputs for the application.

## 9. Final Demonstration Deliverables

The final presentation should include:

1. Problem statement.
2. Proposed solution.
3. System architecture.
4. Data sources and data limitations.
5. Working application demonstration.
6. AI or analytical feature demonstration.
7. Evaluation results.
8. Known limitations.
9. Future improvements.

## 10. Demo Data Policy

If simulated data is used:

- Clearly identify it as simulated.
- Explain why it is used.
- Avoid presenting it as actual astronaut measurements.
- Ensure the demo remains reproducible.

## 11. Final Quality Checklist

- [ ] Data sources are documented.
- [ ] Real and simulated data are distinguished.
- [ ] Data preprocessing is reproducible.
- [ ] AI results have been evaluated where applicable.
- [ ] Frontend and backend are integrated.
- [ ] AI/backend communication works if implemented.
- [ ] The application has been tested.
- [ ] Limitations are documented.
- [ ] The final demonstration is reproducible.
