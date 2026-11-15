# تثبيت التطبيق على الموبايل (APK) / Build & Install the App

> **أهم نقطة / The single most important thing**
> تطبيق مُثبَّت (APK) **لا يمكن** أن يستلم `--dart-define` وقت التشغيل، لذلك عنوان الباك‑إند
> يتم "خبزه" داخل التطبيق **وقت البناء**. اختر العنوان الصحيح أثناء البناء — أو غيّره لاحقًا من
> داخل التطبيق: شاشة اللوج‑إن ← **Backend Connection**.
>
> An installed APK cannot receive `--dart-define` at runtime, so the backend URL is
> **baked in at build time**. Pick the right address while building — or change it later
> from inside the app: login screen → **Backend Connection**.

---

## 1) أسهل طريقة: نزّل APK جاهز من GitHub / Download a ready-made APK

1. افتح المستودع ← **Actions** ← **Build Android App (APK)** ← **Run workflow**.
2. املأ:
   - `backend_url`: العنوان الذي سيستخدمه التطبيق.
     - محاكي أندرويد على نفس الكمبيوتر → `http://10.0.2.2:5000`
     - موبايل حقيقي على نفس الواي فاي → `http://<PC-LAN-IP>:5000` (مثال `http://192.168.1.42:5000`)
     - باك‑إند منشور على الإنترنت → `https://your-api-host`
   - `artifact`: `apk-split` (أصغر، للموبايل) أو `apk-universal` أو `appbundle` (لـ Google Play).
3. بعد ما يخلص الـ run (5–8 دقائق)، في آخر صفحة الـ run هتلاقي **Artifacts** ← نزّل
   `orbitcare-apk-split` ← فك الضغط ← ثبّت `app-arm64-v8a-release.apk` على الموبايل.

> **ملاحظة:** زر *Run workflow* بيظهر بس بعد ما يكون ملف الـ workflow موجود على الفرع
> الرئيسي `main` — يعني بعد دمج الـ PR.
> The button only appears once `.github/workflows/android-app.yml` exists on the default
> branch (`main`), i.e. after the PR is merged.

CLI بديل / Equivalent with the GitHub CLI:

```bash
gh workflow run android-app.yml \
  -f backend_url="http://192.168.1.42:5000" -f artifact="apk-split"
gh run list --workflow=android-app.yml --limit 1
gh run download <run-id> -n orbitcare-apk-split -D ./apk
```

---

## 2) الطريقة المحلية (الأسرع عندك) / Build locally

```bat
:: Windows
scripts\build_apk.bat
```
```bash
# macOS / Linux
./scripts/build_apk.sh
```

السكريبت بيسألك: على أي جهاز هتثبّت؟ (محاكي / موبايل حقيقي / عنوان مخصص) وأي نوع بناء،
ثم ينفّذ الأمر الصح ويعرضلك مسار الملف، ويقترح تثبيته مباشرة عبر `adb`.

The script asks which device you are installing on (emulator / physical phone /
custom URL) and which artifact you want, runs the correct command, prints the output
path, and offers to install it with `adb` right away.

الملف الناتج / Output location:

```
Flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   # split-per-abi
Flutter/build/app/outputs/flutter-apk/app-release.apk             # universal
Flutter/build/app/outputs/bundle/release/app-release.aab          # Play Store
```

---

## 3) الأوامر يدويًا / Raw commands

```bash
cd Flutter
flutter clean && flutter pub get

# موبايل حقيقي على نفس الواي فاي / physical phone on the same Wi-Fi
flutter build apk --release --split-per-abi \
  --dart-define=ORBITCARE_API_BASE_URL=http://192.168.1.42:5000

# محاكي أندرويد / Android emulator
flutter build apk --release --split-per-abi \
  --dart-define=ORBITCARE_API_BASE_URL=http://10.0.2.2:5000

# باك‑إند منشور (HTTPS) / deployed backend
flutter build apk --release --split-per-abi \
  --dart-define=ORBITCARE_API_BASE_URL=https://your-api-host
```

---

## 4) التثبيت على الموبايل / Installing on the phone

**أ) بكابل USB (الأسهل) / USB cable**

```bash
adb devices                                   # الموبايل لازم يظهر / must be listed
adb install -r Flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> فعّل **Developer options → USB debugging** على الموبايل أول مرة.
> Enable Developer options → USB debugging first.

**ب) بدون كابل / Without a cable**

1. انقل ملف الـ APK للموبايل (Google Drive / Telegram / WhatsApp / USB).
2. افتحه من مدير الملفات ← اسمح بـ **Install unknown apps** للمصدر.
3. ثبّت.

> لو ظهر تحذير "App not installed": غالبًا في نسخة قديمة موقّعة بمفتاح مختلف —
> احذف التطبيق القديم الأول ثم ثبّت الجديد.
> If Android says "App not installed", uninstall the previous build first (it was
> signed with a different debug key).

---

## 5) بعد التثبيت: checklist علشان اللوج‑إن يشتغل / After installing

1. الباك‑إند شغّال على الكمبيوتر: `scripts\start_backend.bat` (أو `./scripts/start_backend.sh`).
2. الموبايل والكمبيوتر على **نفس الواي فاي**.
3. الفايرول يسمح بالبورت (Windows — شغّل cmd كمسؤول):
   ```bat
   netsh advfirewall firewall add rule name="OrbitCare API" dir=in action=allow protocol=TCP localport=5000
   ```
4. جرّب من **متصفح الموبايل**: `http://<PC-LAN-IP>:5000/api/health`
   - لو ردّ `{"success":true,...}` والتطبيق فشل → افتح **Backend Connection** في التطبيق وصحّح العنوان واضغط Test ثم Save.
   - لو متردّش → المشكلة في الفايرول/الشبكة/السيرفر، مش في التطبيق. شغّل `cd backend && npm run doctor`.
5. حساب جاهز: `cd backend && npm run seed:demo` ثم ادخل بـ
   `demo.astronaut@orbitcare.local` / `OrbitDemo!2026`.
   (أو اعمل Sign Up وخُد كود الـ OTP من تيرمينال الباك‑إند `[DEVELOPMENT OTP]`.)

---

## 6) الموبايل مش على نفس الشبكة؟ / Phone not on the same network?

عنوان `192.168.x.x` و`10.0.2.2` يشتغلوا **فقط** داخل نفس الشبكة المحلية. لو الموبايل على
بيانات الموبايل أو شبكة تانية، اختار واحدة من:

A LAN IP or `10.0.2.2` only works inside the same local network. If the phone is on
mobile data or another network, pick one:

| الحل / Option | الأمر / How | ملاحظات / Notes |
|---|---|---|
| نفق مؤقت (للعرض) / Temporary tunnel | `ngrok http 5000` أو `cloudflared tunnel --url http://localhost:5000` | ياخد رابط `https://...` → ابنِ الـ APK بالرابط ده |
| نشر الباك‑إند / Deploy the backend | Render / Railway / Fly.io + MongoDB Atlas | أفضل حل للعرض النهائي؛ حط `NODE_ENV=production` و`JWT_SECRET` قوي |
| Hotspot | شغّل hotspot من الكمبيوتر ووصّل الموبايل عليه | العنوان يبقى عنوان الكمبيوتر على شبكة الـ hotspot |

بعد ما تغيّر العنوان، مش لازم تبني APK جديد — غيّره من جوه التطبيق:
**Backend Connection ← اكتب العنوان ← Test ← Save URL**.

You do not need a new APK after that: change the URL inside the app
(**Backend Connection → type → Test → Save URL**).

---

## 7) iOS / آيفون

بناء iOS يحتاج جهاز Mac مع Xcode:

```bash
cd Flutter
flutter build ios --release --dart-define=ORBITCARE_API_BASE_URL=http://<PC-LAN-IP>:5000
```

التثبيت على جهاز حقيقي يحتاج حساب Apple Developer (أو Xcode مجاني للتطوير مع إعادة توقيع كل 7 أيام).
ملف `ios/Runner/Info.plist` فيه استثناء ATS للتطوير المحلي — شيله واستخدم HTTPS قبل أي نشر.

Building for iOS requires a Mac with Xcode, and installing on a real device requires an
Apple Developer account (or free provisioning, re-signed every 7 days). The development
ATS exception in `Info.plist` must be removed and replaced by HTTPS before release.

---

## 8) التوقيع / Signing

- البناء الحالي (`--release`) يوقّع بمفتاح الـ **debug** (`Flutter/android/app/build.gradle.kts`)،
  وده كافٍ للتجربة والتوزيع المباشر على فريق العمل.
- للنشر على Google Play لازم تعمل **upload keystore** وتضيفه في `key.properties`
  (لا تُcommit المفتاح أبدًا)، ثم:
  ```bash
  flutter build appbundle --release --dart-define=ORBITCARE_API_BASE_URL=https://your-api-host
  ```

Release builds currently sign with the debug keystore, which is fine for local testing and
sideloading. For Google Play create an upload keystore referenced from `key.properties`
(never commit it) and build an app bundle instead.

---

## 9) مشاكل البناء الشائعة / Common build problems

| المشكلة / Problem | الحل / Fix |
|---|---|
| `Gradle build failed` / `AAPT2` | `cd Flutter && flutter clean && flutter pub get` ثم أعد البناء |
| `SDK location not found` | افتح المشروع مرة من Android Studio، أو اضبط `ANDROID_HOME` |
| `Command 'flutter' not found` | أضف مجلد Flutter إلى PATH (`D:\flutter_windows_...\flutter\bin`) |
| التطبيق يتصل بس اللوج‑إن يرفض | الحساب مش مُفعّل بالـ OTP → استخدم الحساب التجريبي أو فعّل بالكود من التيرمينال |
| يشتغل في المحاكي ومش يشتغل على الموبايل | العنوان اتخبز `10.0.2.2` → غيّره من **Backend Connection** إلى `http://<PC-LAN-IP>:5000` |
| `CLEARTEXT communication not permitted` | APK قديم مبني قبل إصلاح الـ manifest → ابنِ من أحدث كود |

راجع أيضًا / See also: [`CONNECTION_TROUBLESHOOTING.md`](CONNECTION_TROUBLESHOOTING.md)
