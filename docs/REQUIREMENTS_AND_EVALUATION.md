
# Requirements and Evaluation
## Astronaut Health Monitoring App

## 1. Purpose

This document defines the expected features, functional requirements, and evaluation criteria for the project prototype.

The requirements may be refined as the team reviews the challenge, available datasets, and implementation constraints.

## 2. Functional Requirements

### FR-01: Health Data Display
The system should display selected health measurements in a clear and understandable format.

**Acceptance Criteria:**
- Measurements are displayed with their names and units.
- Missing or unavailable values are handled clearly.
- The interface distinguishes between actual and simulated data.

### FR-02: Health Data Visualization
The system should visualize health measurements and their changes over time.

**Acceptance Criteria:**
- Users can view historical measurements.
- Charts have clear labels and units.
- Time information is displayed correctly.

### FR-03: Health Data Analysis
The AI/Data Science component should analyze available health data to identify potentially unusual patterns.

**Acceptance Criteria:**
- The analysis uses a documented method.
- Results can be evaluated against suitable reference data or test cases.
- The system communicates uncertainty and limitations.

### FR-04: Alerts and Insights
The system should present understandable notifications when predefined conditions or analysis results require attention.

**Acceptance Criteria:**
- Alerts explain what triggered them.
- Alerts do not present experimental model outputs as medical diagnoses.
- The system handles missing or unreliable data appropriately.

### FR-05: Frontend and Backend Integration
The frontend should communicate with the backend through documented interfaces.

**Acceptance Criteria:**
- The frontend can retrieve the required data.
- API responses follow an agreed structure.
- Errors and unavailable services are handled gracefully.

## 3. Non-Functional Requirements

### NFR-01: Usability
The interface should be simple and understandable.

### NFR-02: Reliability
The application should handle missing, invalid, or unavailable data without crashing.

### NFR-03: Maintainability
The codebase should be organized into understandable components.

### NFR-04: Performance
The prototype should respond within a reasonable time for its expected demonstration workload.

### NFR-05: Transparency
The application should identify simulated data and explain the limitations of AI-generated insights.

## 4. MVP Scope

The Minimum Viable Product should prioritize:

1. A working application interface.
2. A dashboard displaying selected health indicators.
3. Historical data visualization.
4. A working backend-data integration.
5. At least one meaningful data-analysis or AI feature, if supported by the available data.
6. A demonstration using documented real or simulated data.

## 5. Out of Scope

The initial prototype does not aim to:

- Diagnose medical conditions.
- Replace professional medical judgment.
- Guarantee detection of every health-related anomaly.
- Implement a complete operational space-mission medical system.
- Support every possible astronaut health indicator.

## 6. Evaluation Criteria

| Area | Evaluation |
|---|---|
| Problem Understanding | Does the solution address the challenge? |
| Functionality | Does the prototype work? |
| Data Handling | Is the data source and processing documented? |
| AI / Data Analysis | Is the chosen method justified and evaluated? |
| Integration | Do frontend, backend, and AI communicate? |
| User Experience | Is information presented clearly? |
| Presentation | Can the team explain and demonstrate the solution? |

## 7. Prioritization

Features are classified into three levels:

- **P0 - Essential:** Required for the core demonstration.
- **P1 - Important:** Adds meaningful value if time allows.
- **P2 - Optional:** Implement only after the core prototype works.

The team should prioritize P0 features before starting P1 or P2 features.

## 8. Requirement Status

Requirements will be tracked through GitHub Issues and the project board.

Possible statuses:

- Proposed
- Approved
- In Progress
- In Review
- Done

## 9. Important Note

The team must not claim that an AI model is medically validated unless appropriate evidence supports that claim.

All experimental results should be presented with their assumptions, limitations, and data-source information.
