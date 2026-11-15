# دليل حل مشكلة الاتصال بالباك‑إند وتسجيل الدخول
# Backend Connection & Login Troubleshooting Guide

> هذا الملف يشرح سبب مشكلة «الابلكيشن مش راضي يربط بالباك‑إند ومش عايز يعدي مرحلة اللوج»
> وكيف تم إصلاحها، خطوة بخطوة.
> This file explains why the app could not reach the backend / could not get past
> login, what was fixed, and how to run everything correctly.

---

## 1) الأسباب الجذرية التي تم إصلاحها / Root causes that were fixed

| # | السبب (عربي) | Root cause (English) | الإصلاح / Fix |
|---|---|---|---|
| 1 | لو شغّلت `flutter run` بدون `--dart-define` كان عنوان الباك‑إند **فاضي**، فكل الطلبات تفشل قبل ما تبدأ. | Without `--dart-define=ORBITCARE_API_BASE_URL=...` the base URL was an empty string, so every request failed instantly. | `lib/core/config/api_config.dart` now resolves a platform default (`10.0.2.2:5000` on Android, `localhost:5000` elsewhere). A plain `flutter run` works. |
| 2 | على **Chrome/Edge (ويب)** النقل كان stub بيرمي `UnsupportedError` → اللوج‑إن يفشل دايمًا حتى مع عنوان صحيح. | On Flutter **Web** the HTTP transport was a stub that threw `UnsupportedError`, so login always failed in a browser. | New universal transport on `package:http` (`csm_http_transport_http.dart`) — works on web, mobile and desktop. |
| 3 | **أندرويد**: إذن `INTERNET` كان موجود في debug/profile بس، و`usesCleartextTraffic` مش متفعّل → HTTP كان محجوب. | **Android**: `INTERNET` was only declared in the debug/profile manifests and cleartext HTTP was blocked by default (Android 9+). | `android/app/src/main/AndroidManifest.xml`: `INTERNET` + `ACCESS_NETWORK_STATE` + `usesCleartextTraffic="true"`. |
| 4 | **macOS**: `com.apple.security.network.client` كان ناقص → التطبيق المعزول (sandbox) مش قادر يفتح أي اتصال. | **macOS**: the `network.client` entitlement was missing, so the sandboxed app could not open any outbound connection. | Added to `DebugProfile.entitlements` and `Release.entitlements`. |
| 5 | **iOS**: ATS كان بيحجب `http://` → «Unable to reach the backend». | **iOS**: App Transport Security blocked plain `http://` local dev traffic. | `NSAppTransportSecurity` added to `ios/Runner/Info.plist` (development only — use HTTPS for production). |
| 6 | لو `MONGO_URI` فاضي أو MongoDB مش شغّال، السيرفر كان **بيقفل قبل ما يسمع على البورت** → التطبيق مش لاقي سيرفر خالص. | With an empty `MONGO_URI` or MongoDB stopped, the server exited **before listening**, so the app found no server at all. | `src/config/db.js`: local default URI, retries, and a clear error with the exact commands to fix it. |
| 7 | لو `JWT_SECRET` مش مظبوط: اللوج‑إن ينجح ثم **كل الطلبات ترجع 401** فيرجّعك لشاشة اللوج‑إن تاني. | With a missing `JWT_SECRET`, login could succeed while every authenticated request returned 401 (kicking you back to the login screen). | `src/utils/token.js` + `src/middleware/authMiddleware.js` now share one secret resolution (dev fallback outside production, hard error in production). |
| 8 | `GET /api/users/me` بيرجّع البروفايل داخل `data.user`، والتطبيق كان بيقرأ `data` مباشرة → بروفايل فاضي باسم "Astronaut". | `GET /api/users/me` nests the profile under `data.user`, but the client parsed `data` itself → an empty profile after session restore. | `OrbitCareApiClient.getMe` now unwraps both shapes and rejects a profile without an id. |
| 9 | مفيش طريقة تغيّر عنوان السيرفر من جوه التطبيق (لازم rebuild كل مرة). | There was no way to change the backend URL from inside the app. | New **Backend Connection** screen (login screen → `Backend Connection`): test `/api/health`, read fix hints, save a URL that applies instantly. |

---

## 2) التشغيل الصحيح من الصفر / Running everything from zero (Windows)

```bat
:: 1) الباك‑إند + MongoDB (نافذة طرفية أولى)
scripts\start_backend.bat

:: 2) حساب تجريبي جاهز ومُفعّل (نافذة طرفية ثانية)
cd backend
npm run seed:demo

:: 3) التطبيق (نافذة طرفية ثالثة) - السكريبت بيسألك على الجهاز ويحط العنوان الصح لوحده
scripts\run_flutter.bat
```

macOS / Linux:

```bash
./scripts/start_backend.sh
(cd backend && npm run seed:demo)
./scripts/run_flutter.sh
```

بيانات الدخول التجريبية / Seeded demo credentials:

- **Email:** `demo.astronaut@orbitcare.local`
- **Password:** `OrbitDemo!2026` (أو قيمة `DEMO_USER_PASSWORD` في `backend/.env`)

> لو الباك‑إند مشتغلش، شغّل التشخيص الكامل — بيقولك بالظبط إيه المشكلة:
> If the backend does not start, run the doctor — it reports exactly what is wrong:
>
> ```bash
> cd backend && npm run doctor        # تقرير فقط / report only
> cd backend && npm run doctor:fix    # ينشئ backend/.env تلقائيًا / creates backend/.env
> ```

---

## 3) العنوان الصحيح لكل جهاز / Which URL for which device

| الجهاز / Device | العنوان / URL | ملاحظة / Note |
|---|---|---|
| Android emulator | `http://10.0.2.2:5000` | `10.0.2.2` = الجهاز المضيف من داخل المحاكي فقط |
| iPhone simulator / macOS / Windows / Linux / Chrome | `http://localhost:5000` | نفس الجهاز |
| موبايل حقيقي (Android/iOS) | `http://<PC-LAN-IP>:5000` | لازم نفس شبكة الواي فاي + فتح البورت في الفايرول |

معرفة الـ LAN IP / Find your LAN IP:

```bat
:: Windows
ipconfig        :: IPv4 Address -> مثلا 192.168.1.42
```
```bash
# macOS
ipconfig getifaddr en0
# Linux
ip -4 -o addr show scope global
```

فتح البورت في فايرول ويندوز / Allow the port through the Windows firewall:

```bat
netsh advfirewall firewall add rule name="OrbitCare API" dir=in action=allow protocol=TCP localport=5000
```

---

## 4) شاشة «Backend Connection» داخل التطبيق / In-app connection screen

من شاشة تسجيل الدخول اضغط **Backend Connection** (أو من أيقونة `settings_ethernet` في الصفحة الرئيسية):

1. يعرض العنوان الفعّال ومصدره (runtime / `--dart-define` / افتراضي).
2. زر **Test** يعمل `GET /api/health` ويترجم الخطأ لسبب واضح + خطوات إصلاح.
3. زر **Save URL** يحفظ العنوان الجديد ويسري **فورًا بدون rebuild**.
4. **Reset to build default** يرجّع العنوان الافتراضي.

Open **Backend Connection** from the login screen (or the network icon in the home app bar): it shows the active URL and its source, tests `/api/health`, translates the failure into concrete fix hints, and saves a new URL that takes effect immediately — no rebuild needed.

---

## 5) رسالة الخطأ ← السبب / Error message → cause

| الرسالة في التطبيق / Message | السبب الأكثر احتمالًا / Likely cause | الحل / Fix |
|---|---|---|
| `Unable to reach the OrbitCare backend at ...` | السيرفر مش شغّال، أو عنوان/بورت غلط، أو الفايرول حاجز | `scripts\start_backend.bat`، ثم `Test` من شاشة الاتصال |
| `Request to ... timed out` | الفايرول بيرمي الباكيتات، أو الموبايل على شبكة تانية | افتح البورت 5000، وتأكد من نفس الواي فاي |
| `Android blocked the plain HTTP connection` | APK قديم مبني قبل إصلاح الـ manifest | `flutter clean && flutter run` بأحدث كود |
| `Could not resolve the host ...` | خطأ كتابي في العنوان | صحّح العنوان في شاشة الاتصال |
| `Invalid email or password` | بيانات غلط | استخدم الحساب التجريبي أو `npm run seed:demo` |
| `Please verify your email before logging in` | الحساب مش مُفعّل بالـ OTP | اضغط **Send Verification OTP**، وخد الكود من تيرمينال الباك‑إند `[DEVELOPMENT OTP]` |
| `Your session expired. Please sign in again.` | التوكن انتهت صلاحيته أو `JWT_SECRET` اتغيّر | سجّل دخول تاني؛ ثبّت `JWT_SECRET` في `backend/.env` |
| الصفحة الرئيسية فاضية بعد اللوج‑إن | مشكلة `/api/users/me` القديمة (بند 8) | تم إصلاحها — حدّث الكود |

---

## 6) تشخيص يدوي سريع / Quick manual checks

```bash
# 1) هل الباك‑إند شغّال؟
curl http://127.0.0.1:5000/api/health
#  -> {"success":true,"message":"OrbitCare API is running","database":"connected",...}

# 2) هل MongoDB شغّال؟
docker run -d -p 27017:27017 --name orbitcare-mongo mongo:7    # أو mongod محليًا

# 3) هل البورت محجوز من عملية تانية؟
netstat -ano | findstr :5000      # Windows
lsof -i :5000                     # macOS / Linux

# 4) هل الموبايل شايف الكمبيوتر؟ (من متصفح الموبايل)
http://<PC-LAN-IP>:5000/api/health
```

لو الخطوة 4 نجحت على الموبايل والتطبيق فشل → المشكلة في عنوان التطبيق (افتح شاشة Backend Connection).
If step 4 works in the phone browser but the app fails, the app is pointing at the wrong URL — open the Backend Connection screen.

---

## 7) ملاحظات أمان / Security notes

- `usesCleartextTraffic` و`NSAllowsArbitraryLoads` و`JWT_SECRET` الاحتياطي كلها **للتطوير المحلي فقط** (hackathon prototype).
- للنشر: استخدم HTTPS، وشيل `NSAllowsArbitraryLoads`، واضبط `NODE_ENV=production` مع `JWT_SECRET` قوي (السيرفر بيرفض يشتغل من غيره في الإنتاج).
- لا تضع عنوان سيرفر حقيقي في الكود؛ استخدم `--dart-define=ORBITCARE_API_BASE_URL=...`.

These development-only settings (`usesCleartextTraffic`, `NSAllowsArbitraryLoads`, the dev JWT fallback) must be replaced before deploying: use HTTPS, remove `NSAllowsArbitraryLoads`, and run with `NODE_ENV=production` plus a strong `JWT_SECRET` (the server refuses to start without one in production). Never hardcode a real hostname — pass it with `--dart-define=ORBITCARE_API_BASE_URL=...`.
