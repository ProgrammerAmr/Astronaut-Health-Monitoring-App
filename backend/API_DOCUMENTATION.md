# OrbitCare – Backend API Documentation

## 1. Project Overview

OrbitCare is an Astronaut Health Monitoring System.

The backend provides APIs for:
- User authentication and email verification.
- Astronaut profile management.
- Health measurements management.
- Dashboard statistics.
- Health alerts.
- Health reports.

**Backend Stack:** Node.js, Express.js, MongoDB, Mongoose, JWT.

---

## 2. Base URLs

| Environment | Base URL |
|---|---|
| Local computer | `http://localhost:5000/api` |
| Android Emulator | `http://10.0.2.2:5000/api` |
| Physical Android device | `http://YOUR_COMPUTER_LAN_IP:5000/api` |

Replace `YOUR_COMPUTER_LAN_IP` with the computer's local IP address when testing on a physical device.

## 3. General API Conventions

- Request and response bodies use JSON.
- Protected endpoints require a JWT token.
- MongoDB IDs are returned as strings.
- Dates use ISO 8601 format.
- Successful responses generally include `success: true`.
- Error responses include `success: false` and a message.

### Authorization Header

For protected endpoints, send:

```http
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json
```

The token is returned after successful login or signup verification.

---

# 4. Authentication APIs

All authentication endpoints use:

`/auth`

### 4.1 Register

**POST** `/auth/register`

Creates an account and sends an OTP for email verification.

Request:

```json
{
  "fullName": "Test Astronaut",
  "email": "astronaut@example.com",
  "password": "Password123"
}
```

You can use `name` instead of `fullName`.

Validation:
- Name, email, and password are required.
- Password must contain at least 8 characters.
- An already verified email cannot register again.

Success response:

```json
{
  "success": true,
  "message": "Account created. Verification code sent to your email."
}
```

### 4.2 Login

**POST** `/auth/login`

Request:

```json
{
  "email": "astronaut@example.com",
  "password": "Password123"
}
```

Success response:

```json
{
  "success": true,
  "token": "JWT_TOKEN",
  "user": {
    "id": "USER_ID",
    "name": "Test Astronaut",
    "email": "astronaut@example.com"
  }
}
```

The user must verify their email before logging in.

### 4.3 Send OTP

**POST** `/auth/send-otp`

Request:

```json
{
  "email": "astronaut@example.com",
  "purpose": "signup"
}
```

Supported purposes:
- `signup`
- `reset_password`

If `purpose` is omitted, it defaults to `reset_password`.

Success response:

```json
{
  "success": true,
  "message": "OTP sent successfully"
}
```

### 4.4 Verify OTP

**POST** `/auth/verify-otp`

Request for signup:

```json
{
  "email": "astronaut@example.com",
  "otp": "123456",
  "purpose": "signup"
}
```

Success response for signup:

```json
{
  "success": true,
  "message": "OTP verified. Account activated successfully.",
  "token": "JWT_TOKEN",
  "user": {
    "id": "USER_ID",
    "name": "Test Astronaut",
    "email": "astronaut@example.com"
  }
}
```

For password reset:

```json
{
  "email": "astronaut@example.com",
  "otp": "123456",
  "purpose": "reset_password"
}
```

Successful password-reset verification returns a confirmation message. The OTP remains valid until the reset-password endpoint consumes it.

OTP expiration: 10 minutes.

### 4.5 Reset Password

**POST** `/auth/reset-password`

Request:

```json
{
  "email": "astronaut@example.com",
  "otp": "123456",
  "newPassword": "NewPassword123"
}
```

Success response:

```json
{
  "success": true,
  "message": "Password reset successfully"
}
```

Password must contain at least 8 characters.

---

# 5. User Profile APIs

All endpoints in this section require authentication.

### 5.1 Get Current User Profile

**GET** `/users/me`

Headers: Authorization required.

Returns the authenticated user's profile.

### 5.2 Update Current User Profile

**PATCH** `/users/me`

Request example:

```json
{
  "name": "Test Astronaut",
  "avatarUrl": "https://example.com/avatar.png",
  "mission": {
    "name": "ISS Mission",
    "role": "Astronaut",
    "status": "Active"
  },
  "preferences": {
    "notificationsEnabled": true,
    "temperatureUnit": "C"
  }
}
```

Supported profile fields:
- `name`
- `email`
- `avatarUrl`
- `mission`
- `preferences`

Temperature unit values: `C` or `F`.

Note: `avatarUrl` stores an image URL. This endpoint does not upload image files.

### 5.3 Change Password

**PATCH** `/users/change-password`

Request:

```json
{
  "currentPassword": "OldPassword123",
  "newPassword": "NewPassword123"
}
```

The new password must contain at least 8 characters.

### 5.4 Get All Users (Admin Only)

**GET** `/users`

Requires an authenticated admin account.

---

# 6. Health Measurements APIs

All measurement endpoints require authentication.

Base path: `/measurements`

### 6.1 Create Measurement

**POST** `/measurements`

Request example:

```json
{
  "heartRate": 80,
  "pulseRate": 80,
  "respiratoryRate": 17,
  "spo2": 98,
  "temperature": 37.1,
  "bloodPressure": {
    "systolic": 120,
    "diastolic": 80
  },
  "bloodSugar": 95,
  "sleep": {
    "durationMinutes": 420,
    "quality": "good"
  },
  "activity": {
    "steps": 5000,
    "calories": 250,
    "durationMinutes": 30,
    "level": "moderate"
  },
  "measuredAt": "2026-11-15T10:00:00.000Z",
  "source": "manual"
}
```

Supported fields:
- `heartRate`
- `pulseRate`
- `respiratoryRate`
- `spo2`
- `temperature`
- `bloodPressure`
- `bloodSugar`
- `sleep`
- `activity`
- `measuredAt`
- `source`

Source values:
- `sensor`
- `manual`
- `imported`

Sleep quality:
- `poor`
- `fair`
- `good`
- `excellent`

Activity level:
- `low`
- `light`
- `moderate`
- `high`
- `intense`

`measuredAt` and `source` are optional. The backend provides defaults.

### 6.2 Get Measurements

**GET** `/measurements`

Returns the authenticated user's measurements.

Supported query parameters:

| Parameter | Description |
|---|---|
| `type` | Filter by measurement type |
| `period` | `daily`, `weekly`, or `monthly` |
| `from` | Start date |
| `to` | End date |
| `startDate` | Alternative start date |
| `endDate` | Alternative end date |
| `page` | Page number |
| `limit` | Number of records (maximum 100) |

Example:

```http
GET /measurements?type=temperature&period=weekly
```

Other examples:

```http
GET /measurements?page=1&limit=10
GET /measurements?period=daily
GET /measurements?from=2026-11-01&to=2026-11-15
```

Available measurement types include:
- `heartRate`
- `pulseRate`
- `respiratoryRate`
- `spo2`
- `temperature`
- `bloodPressure`
- `bloodSugar`
- `sleep`
- `activity`

### 6.3 Get Measurement by ID

**GET** `/measurements/:id`

Example:

```http
GET /measurements/MEASUREMENT_ID
```

### 6.4 Update Measurement

**PUT** `/measurements/:id`

Send the fields that need to be updated in the JSON body.

### 6.5 Delete Measurement

**DELETE** `/measurements/:id`

Deletes the specified measurement if the authenticated user owns it.

---

# 7. Dashboard APIs

All dashboard endpoints require authentication.

### 7.1 Get Dashboard Overview

**GET** `/dashboard/overview`

Returns dashboard statistics, including:
- Total measurements.
- Unread alerts count.
- Average heart rate.
- Average SpO2.
- Average respiratory rate.
- Average blood sugar.
- Average temperature.
- Latest measurement.
- Latest measurements.

Example:

```http
GET /dashboard/overview
```

---

# 8. Alerts APIs

All alert endpoints require authentication.

### 8.1 Get Alerts

**GET** `/alerts`

Returns alerts belonging to the authenticated user.

Optional query parameter:

`isRead=true` or `isRead=false`

Example:

```http
GET /alerts?isRead=false
```

### 8.2 Create Alert (Admin Only)

**POST** `/alerts`

Requires an authenticated admin account.

Request:

```json
{
  "astronaut": "USER_ID",
  "title": "High Heart Rate",
  "message": "Heart rate is above the configured threshold.",
  "severity": "high",
  "relatedMeasurement": "MEASUREMENT_ID"
}
```

Severity values:
- `low`
- `medium`
- `high`
- `critical`

`relatedMeasurement` is optional.

### 8.3 Mark Alert as Read

**PATCH** `/alerts/:id/read`

Marks the specified alert as read.

---

# 9. Reports APIs

All report endpoints require authentication.

### 9.1 Get Health Report

**GET** `/reports`

Supported query parameter:

`period=daily|weekly|monthly`

Example:

```http
GET /reports?period=weekly
```

Optional date filters:
- `from`
- `to`

The report includes aggregated health data such as:
- Average heart rate.
- Average SpO2.
- Average respiratory rate.
- Average blood sugar.
- Average temperature.
- Total steps.
- Total calories.
- Total sleep duration.
- Number of measurements.

---

# 10. Health Check

**GET** `/health`

Example:

```http
GET /health
```

Used to check whether the backend server is running.

---

# 11. Important Integration Notes

1. Always store the JWT token after successful login or signup verification.
2. Send the token in the Authorization header for protected APIs.
3. Use `10.0.2.2` instead of `localhost` when testing from an Android Emulator.
4. For a physical device, use the computer's LAN IP address and ensure both devices are on the same network.
5. OTP delivery depends on the configured email service. In development, OTP may be printed in the backend terminal.
6. The backend stores measurement data; it does not independently diagnose medical conditions.
7. Alerts are retrieved from the database. They must be created by an authorized admin or another integrated system. They are not automatically generated by the measurement API.
8. `avatarUrl` accepts a URL, not a multipart image upload.
9. Do not hardcode JWT tokens in the Flutter application.
10. Do not expose passwords, OTPs, or secret environment variables in client-side code.

---

# 12. Error Handling

Common HTTP status codes:

| Status | Meaning |
|---|---|
| 200 | Request successful |
| 201 | Resource created |
| 400 | Invalid request or validation error |
| 401 | Missing or invalid authentication |
| 403 | Forbidden or email not verified |
| 404 | Resource not found |
| 409 | Account already exists |
| 429 | Too many OTP attempts |
| 500 | Internal server error |

Example error response:

```json
{
  "success": false,
  "message": "Invalid email or password"
}
```

---

**Base API path:** `/api`

**Backend:** Node.js + Express.js + MongoDB

**Documentation status:** Backend endpoints documented for Flutter integration.

---

# 13. Cognitive State Monitoring Research API (DEC-001)

> **Experimental research prototype — not a medical diagnosis or flight-certified system.** No trained or validated CSM model artifact is currently shipped. Live-sensor inference is rejected, raw physiological waveforms are not accepted or persisted, and outputs do not trigger automatic alerts.

Both endpoints require a valid `Authorization: Bearer <JWT>` header. Non-admin users may only request analysis for their own account (`astronautId` omitted or matching the authenticated user ID; otherwise `403 Forbidden`).

Configure upstream connection via environment variables (see `backend/.env.example`):
- `CSM_AI_SERVICE_URL` — base URL of the Python FastAPI AI service (no hardcoded default)
- `CSM_AI_TIMEOUT_MS` — request timeout in milliseconds (default `5000`, clamped to `500–30000`)

### 13.1 Get Service Status & Limitations

**GET** `/cognitive-state/status`

Returns service availability, `registered_model_available`, `model_status.validated` (`false`), fixed limitations, and disclaimer (never claims model health). Returns `503`/`504` safely when unconfigured, unreachable, or timed out.

### 13.2 Request Cognitive State Analysis

**POST** `/cognitive-state/analyze`

Enforces a `32 KiB` body-size cap and strict server-side schema validation.

```json
{
  "mode": "synthetic_demo | research_replay",
  "sessionId": "optional-session-id",
  "astronautId": "optional-self-id-or-admin-target",
  "windowEndSec": 120.0,
  "dataProvenance": "synthetic | simulated | real_nasa_csm_replay",
  "signalQuality": {
    "valid": true,
    "sqi_score": 0.95,
    "reasons": []
  }
}
```

- `mode: "live_sensor"` or `dataProvenance: "live_sensor"` → rejected (`400`, `LIVE_SENSOR_UNSUPPORTED`).
- Raw physiological signal fields (`eeg`, `ecg`, `gsr`, `resp`, `raw_signals`, `samples`) → rejected (`400`, `RAW_SIGNAL_NOT_ACCEPTED`).
- When no verified model artifact exists, SQI is low/missing, or upstream is unavailable/timed out → returns safe abstention (`INSUFFICIENT_DATA` or `ERROR`) with `prediction.abstained: true` and `prediction.probabilities: null` (never substitutes or invents predictions).
