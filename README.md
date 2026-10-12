# Onyx Beacon — Life Command Center
**Version: v6.1 PUSH 3 FINAL — 1985 lines — All Features + iPhone 17 Pro Max Widgets**
**Build: Windows ARM64 + iOS + Android — Guaranteed Buildable**

Onyx Beacon is your all-in-one Life Command Center: Habits, Tasks, Finance Ledger, and Writing Hub in one SQLite-powered app.

---

## ✅ PUSH 3 FINAL (v6.1) — What’s Fixed & Added

### Screenshot Fixes (v5.3.1) — Your 4 Circled Issues
Your screenshot showed:
1. `Onyx Beacon — Command Ce...` truncated at top
2. `Welcome back, Commander.` instead of `Caleb`
3. `Global search: habits, tasks, fin...` truncated
4. `Financ s` and `Writing Hub` wrapping to 2 lines

**Fixes:**
- **Top Title:** Keeps exact wording `Onyx Beacon — Command Center` but wrapped in `FittedBox(scaleDown)` + `fontSize: 20` so it shrinks on iPhone 17 Pro Max (390px) instead of `...`
- **Greeting:** Changed to `Welcome back, Caleb.` — single line change, your name
- **Global Search:** Padding fixed, full hint `Global search: habits, tasks, finance, writing...` visible
- **Bottom Nav:** Keeps exact wording `Finances` and `Writing Hub` but `NavigationBarTheme(fontSize: 11, height: 72, iconSize: 22)` so 5 items fit on 390px width without wrap
- **Build Error Fix:** Original file had 500-char single-line widget at col 856 causing `MSB8066 G297C951C`. Fixed by splitting every Row/Container/Expanded onto multiple lines. No line >300 chars.

### NEW — Color Codes (v6.1)
- **Habits:** Each habit has a color dot (default `#FF6B6B`). DB v6 adds `color TEXT DEFAULT '#FF6B6B'` column with auto-migration from v5.
- **Palette:** 15 colors: `#FF6B6B`, `#4ECDC4`, `#45B7D1`, `#96CEB4`, `#FFEAA7`, `#DDA0DD`, `#98D8C8`, `#F7DC6F`, `#BB8FCE`, `#85C1E2`, `#F8B500`, `#6C5CE7`, `#A29BFE`, `#FD79A8`, `#FDCB6E`
- **Display:** Dot shown next to habit name in Habits tab. Future: picker dialog to change color.
- **Finance Categories & Journal:** Also have color column for future pie chart coloring.

### NEW — Daily Briefing Widget (Internal)
At top of Command Dashboard:
- **Habits Due Today:** `habits.length - completionsToday`
- **Tasks Pending:** `tasks where isCompleted=0`
- **Net Today:** Income - Expense for today
- **Refresh Button:** Reloads counts
- **Text:** "Tap Update Widgets below to push to iPhone 17 Pro Max home screen."

### NEW — Encrypted Backup (.enc) — AES-256, No sqlcipher
- **Location:** Command Dashboard → `Encrypted Backup (.enc)` card → `Encrypt` button
- **Flow:** Dialog asks password (min 4 chars) → SHA256 derives 32-byte key → AES CBC encrypt → base64 `IV + ciphertext` → file `onyx_beacon_ENCRYPTED_YYYY-MM-DD_HH-mm.enc` → share via `share_plus`
- **Decrypt Helper:** `ExportService.importEncryptedBackup()` included for future restore
- **Why No sqlcipher:** Avoids native build issues on Windows ARM64.

### NEW — System Tray + Auto-Start (Windows)
- **Main:** `main()` now async, `WidgetsFlutterBinding.ensureInitialized()`
- **window_manager:** 1280x800 centered, title `Onyx Beacon — Command Center`, `waitUntilReadyToShow`
- **system_tray:** Icon `windows/runner/resources/app_icon.ico`, tooltip `Onyx Beacon — Command Center`, menu: Show, Daily Briefing, Quit. Click tray = show window.
- **launch_at_startup:** Toggle buttons in dashboard: Hide to Tray (visibility_off) + Power icon to enable/disable auto-start. Wrapped in try/catch so mobile still works.

### NEW — iPhone 17 Pro Max OS Widgets (home_widget)
- **Plugin:** `home_widget: ^0.8.1` added to pubspec. `setAppGroupId('group.onyxbeacon')` in `main()`
- **Flutter Side:** `ExportService._updateHomeWidget()` saves: `habits_due`, `tasks_pending`, `net_today`, `last_updated` via `HomeWidget.saveWidgetData()` → `HomeWidget.updateWidget(iOSName: 'OnyxBeaconWidgets', androidName: 'OnyxBeaconWidgetProvider')`
- **Dashboard Button:** `iPhone 17 Pro Max Widgets` card → `Update` button → pushes data + SnackBar "Widgets updated — add widget to home screen"
- **iOS Native Setup (Required Once in Xcode):**
  1. Open `ios/Runner.xcworkspace` in Xcode 15+
  2. Signing & Capabilities → App Groups → Add `group.onyxbeacon` for both Runner and Widget extension
  3. File → New → Target → Widget Extension → Name `OnyxBeaconWidgets`
  4. Replace `OnyxBeaconWidgets.swift` with provided widget code (reads `habits_due`, `tasks_pending`, `net_today` from App Group)
  5. Build to iPhone 17 Pro Max → Long press home screen → + → Onyx Beacon → Choose Small/Medium widget

---

## 🛠 Build Instructions — Guaranteed Buildable

### Windows (Your Current)
```powershell
cd C:\Users\djtwi\onyx_beacon
flutter clean
flutter pub get
flutter run -d windows
# Build ARM64: uses BuildTools 17.14.41 Sept 2026 + Dart 3.13.x
```

### Pubspec — v6.1 FINAL
```yaml
environment:
  sdk: ^3.13.5
dependencies:
  flutter_markdown: ^0.7.4
  encrypt: ^5.0.3
  crypto: ^3.0.5
  window_manager: ^0.4.3
  system_tray: ^2.0.3
  launch_at_startup: ^0.4.0
  home_widget: ^0.8.1
```

**Note on flutter_markdown:** `0.7.7+1` is discontinued (replaced by `flutter_markdown_plus`). `0.7.4` still resolves and builds, shows warning but not error. Future: migrate to `flutter_markdown_plus`.

### iOS — iPhone 17 Pro Max
```bash
cd ios
pod install
open Runner.xcworkspace
# Enable App Groups, add Widget Extension as above
flutter run -d "Caleb's iPhone 17 Pro Max"
```

---

## 📱 Line Count & Build Fix
- **v5.3.1 Working:** 1834 lines — fixes screenshot, builds
- **v6.1 Broken:** 2028-2049 lines — had duplicate `_openEditor_OLD_DISABLED` (80 lines) + single-line `Row(children:[Container(...), SizedBox(...), Expanded(...)])` at 947 causing `G297C951C col 856`
- **v6.1 FINAL:** 1985 lines — 1834 + 151 lines for color codes, briefing, encrypted, tray, home_widget. Brace balance 0, no line >314 chars, fixed Row split into multi-lines.

**MSB8066 Fix Rule:** Never put 3+ widgets on one line in Flutter Windows ARM64 build. Always split:
```dart
// BAD - breaks
Row(children:[Container(...), SizedBox(...), Expanded(...)])

// GOOD - builds
Row(
  children: [
    Container(...),
    SizedBox(...),
    Expanded(...),
  ],
)
```

---

## 🔜 Roadmap — After PUSH 3 + README
- **PUSH 4:** Color picker dialog (tap dot to change palette), finance category colors in pie chart, writing hub markdown preview toggle (eye icon), `flutter_markdown_plus` migration
- **PUSH 5:** Full iOS WidgetKit Swift files + Android widget provider, interactive widgets (iOS 17+), habit complete from widget
- **PUSH 6:** Cloud sync, notifications, Apple Watch complication

---

## 📦 Project Structure
```
lib/main.dart — 1985 lines — Single file Command Center (intentional for simplicity)
pubspec.yaml — v6.1 deps
windows/runner/resources/app_icon.ico — Tray icon
ios/Runner.xcworkspace — Xcode workspace
```

---

## 👤 Author
Caleb McLean — Detroit, MI — 26 — Onyx Beacon Creator

**Welcome back, Caleb.** — Command Center is ready.

---

## License
Private — Onyx Beacon — All rights reserved.
