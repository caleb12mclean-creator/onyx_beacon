# Onyx Beacon — Life Command Center

**PUSH 3.0 FINAL Interactive — 2191 lines — FREE Tap-to-Act Widgets — Buildable**
**Home:** Detroit, MI | **Device:** iPhone 17 Pro Max + Windows ARM64 | **Status:** ✅ Works (FINAL3_FIXED)

Your life's command center. Habits, Tasks, Finance, Writing Hub — encrypted, local, interactive.

---

## ✅ PUSH 3.0 FINAL (2191 lines) — What Changed

### FIXED2 vs FINAL2 — Difference

| | FIXED2 (1986 lines) | FINAL2 Interactive (2191 lines) — CURRENT |
|---|---|---|
| **Daily Briefing** | Static numbers only | **Tappable: Tap to act** |
| Habits Due tap | ❌ | ✅ Dialog with due habits + color dot → Tap check → `toggleHabitCompletion()` → SnackBar 🔥 |
| Tasks tap | ❌ | ✅ Dialog with pending tasks → Tap check → `updateTaskCompletion()` → SnackBar |
| Net Today tap | ❌ | ✅ Jumps to Finance tab via `setTab(3)` |
| InkWell count | 0 | 3 |
| dueHabits/pendingTasks | ❌ | ✅ Lists in state |
| Build error | None | Fixed GEE892CD5 `& NAVIGATION` duplicate header at line 759 |
| Brace | 0 | **0** |
| Duplicates | 1 state | **1 state — No duplicate** |

**FIXED2:** Shows `3 Habits Due`, `5 Tasks`, `$42` — refresh only.
**FINAL2:** Tap `3` → see which 3 habits → complete one without leaving dashboard.

---

### Features (All Free, No $99, No Mac)

#### 1. Screenshot Fixes (from your circled screenshot)
- Title: `Onyx Beacon — Command Center` — FittedBox so no `...` on iPhone 17 Pro Max 390px
- Greeting: `Welcome back, Caleb.` — not Commander
- Search: `Global search: habits, tasks, finance, writing...` — full visible
- Nav: `Finances` + `Writing Hub` — fontSize 11, height 72, icon 22 — 5 items fit no wrap
- Fix: Split long `Row(children:[Container,SizedBox,Expanded])` into multi-lines — fixes `G297C951C col 856`

#### 2. Color Codes — 15 Colors
```dart
#FF6B6B #4ECDC4 #45B7D1 #96CEB4 #FFEAA7 #DDA0DD #98D8C8 #F7DC6F #BB8FCE #85C1E2 #F8B500 #6C5CE7 #A29BFE #FD79A8 #FDCB6E
```
DB v6: `color TEXT DEFAULT '#FF6B6B'` auto-migration. Dot shown in Habits tab + briefing dialog.

#### 3. Encrypted Backup (.enc) — AES-256
Dashboard → Encrypted Backup (.enc) → Encrypt → password → SHA256 → AES CBC → `onyx_beacon_ENCRYPTED_*.enc` → share via `share_plus`
Decrypt: `ExportService.importEncryptedBackup()`

#### 4. System Tray + Auto-Start (Windows)
`window_manager` 1280x800 centered, `system_tray` icon `app_icon.ico`, menu Show/Daily Briefing/Quit, `launch_at_startup` toggle (hide to tray + power icon). Try/catch so mobile still works.

#### 5. Interactive Daily Briefing — FREE Widget (This PUSH)
Top of Command Dashboard. Code:

```dart
class DailyBriefingWidget extends StatefulWidget {
  final Function(int)? onNavigateToTab; // For Finance/Tasks jump
}
class _DailyBriefingWidgetState {
  List<Map> dueHabits, pendingTasks; // Due today
  void _showDueHabitsDialog() // InkWell tap → ListTile + check button → toggleHabitCompletion
  void _showPendingTasksDialog() // InkWell tap → ListTile + check → updateTaskCompletion
}

// In Dashboard:
DailyBriefingWidget(onNavigateToTab: (idx) => shell.setTab(idx))
```

**Why FREE?** Internal widget, no App Groups needed. Real iOS home screen widgets need App Groups ($99).

#### 6. iPhone 17 Pro Max OS Widget Prep (For PUSH 4)
- `home_widget: ^0.8.1` → `setAppGroupId('group.onyxbeacon')`
- Flutter saves `habits_due`, `tasks_pending`, `net_today`, `last_updated`
- Swift file already pushed: `ios/OnyxBeaconWidgets/OnyxBeaconWidgets.swift` (212 lines) — reads App Group, Small/Medium/Large
- Waiting for Mac mini + $99 to build

---

## 📱 Install — PUSH 3.0 FINAL3_FIXED (2191 lines)

### Windows — Works Now
```powershell
cd C:\Users\djtwi\onyx_beacon
Remove-Item lib\main.dart -Force
Copy-Item $HOME\Downloads\main_PUSH3_0_INTERACTIVE_FINAL3_FIXED.dart lib\main.dart -Force
flutter clean
flutter pub get
flutter run -d windows
# Tap Daily Briefing numbers → dialogs work
```

### iPhone 17 Pro Max — Free Cable (No $99 yet)
```powershell
flutter run -d "iPhone 17 Pro Max"
# Command → Daily Briefing → Tap Habits Due → complete
```

### Build Validation (This file)
- Lines: 2191
- Brace diff: 0
- Duplicate `_DailyBriefingWidgetState`: 1 (good)
- Long lines >400: 0
- GEE892CD5 `===` error: Fixed (was ` & NAVIGATION` leftover at line 759)
- G297C951C col 856: Fixed (split Rows)
- DB methods: `toggleHabitCompletion`, `updateTaskCompletion` exist

---

## 🔒 Why No Real Home Screen Widgets For Free?

**iOS locks App Groups behind $99 Apple Developer Program.**

- Real widget needs `group.onyxbeacon` so Runner ↔ Widget Extension share data
- Free Apple ID can't create App Groups → Codemagic shows "No signing files"
- `home_widget` plugin is free, WidgetKit is free, but entitlement is paid

**What free CAN do:**
- Internal interactive briefing (PUSH 3.0) — ✅ You have it
- Shortcuts widget → Open Onyx Beacon button — free, no data
- Android home screen widgets — ✅ Free, sideload APK

**What $99 unlocks (PUSH 4):**
- App Groups + TestFlight + App Store + Small/Medium/Large + Lock Screen + StandBy widgets for iPhone 17 Pro Max

---

## 🗓️ PUSH 4 — When You Get Mac mini + $99

1. Enroll https://developer.apple.com/programs/ $99
2. developer.apple.com → Identifiers → New App Group `group.onyxbeacon` → Assign to `com.caleb.onyxbeacon` + `com.caleb.onyxbeacon.OnyxBeaconWidgets`
3. Xcode: Open `ios/Runner.xcworkspace` → Signing → App Groups → check `group.onyxbeacon` for Runner + OnyxBeaconWidgetsExtension
4. File → New → Target → Widget Extension → `OnyxBeaconWidgets` → Replace Swift with `ios/OnyxBeaconWidgets/OnyxBeaconWidgets.swift` (already pushed)
5. Build → Long press home → + → Onyx Beacon

Or Codemagic: Connect GitHub + Apple Dev → Build M2 Mac → TestFlight.

No Flutter code change — data already saved.

---

## 🛠️ Stack
Flutter 3.24+ stable, sqflite, encrypt 5.0.3, window_manager 0.4.3, system_tray 2.0.3, launch_at_startup 0.4.0, home_widget 0.8.1, fl_chart 0.71.0, share_plus

**Files:**
- `lib/main.dart` — 2191 lines — FINAL3_FIXED — Interactive briefing
- `ios/OnyxBeaconWidgets/OnyxBeaconWidgets.swift` — 212 lines — PUSH 4 ready
- `pubspec.yaml` — PUSH 3 deps

---

## 📦 History
- v5.3.1: 1834 lines — Screenshot fixes, builds
- v6.1 FINAL: 1985 lines — Color, briefing static, encrypted, tray, home_widget data
- PUSH 3.0 FIXED2: 1986 lines — setTab, static
- **PUSH 3.0 FINAL Interactive FINAL3_FIXED: 2191 lines — Tap to complete habits/tasks, tap Net Today to Finance, fix header bug — CURRENT, works**

---

## 👤 Caleb McLean — Detroit, MI

**Welcome back, Caleb.** Tap your Daily Briefing.

**PUSH 3.0 DONE (Free). PUSH 4 = Mac mini + $99 = Real iPhone 17 Pro Max home screen widgets.**

---
License: Private — Onyx Beacon — All rights reserved.
