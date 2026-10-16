# Onyx Beacon — PUSH 5 AERO iPhone First — True Offline Real AI
**Version: 1.0.0+11 — 3700+ lines — iPhone 13 + iPhone 17 Pro Max Primary — Windows is Builder Only**
**Detroit, MI — Caleb McLean — Command Center**

> This README is the HANDOFF for Claude (or any AI editor) to fix all mistakes, inconsistencies, and missed acceptance criteria. Assume everything I asked for TODAY worked. Now make it perfect.

---

## 0. Executive Summary — What Is Onyx Beacon?

All-in-one Life Command Center in ONE `lib/main.dart` (intentional):
- **Habits** + streaks + heatmap
- **Tasks** (todo)
- **Finance Ledger** (income/expense, categories, CSV/PDF export)
- **Writing Hub** (journal_entries) with Kanban (Idea/Drafting/Revision/Complete), word_count, order_index, color
- **Command Dashboard** (metrics, cross-module analytics, weekly PDF, P2P sync prep, AERO)
- **AERO** — Real AI + Bible — 4-engine architecture, 100% offline capable on ANY iPhone

**Philosophy:** Local-first, Zero Cloud, Zero Fees, SQLite is source of truth, iPhone is primary device, Windows Surface Pro is only used to BUILD and optionally host Ollama on same Wi-Fi.

---

## 1. CORE PRINCIPLE — iPhone First (Non-Negotiable)

**This is the #1 acceptance criteria that was violated before:**

1. **iPhones are PRIMARY FOCUS.** Windows is REALLY ONLY USED TO BUILD and CAN BE ADDRESSED LATER.
2. **Apple Intelligence Architecture must ACTUALLY FUCKING FUNCTION, NOT JUST THESE TEXT** — not just cards that describe engines, but real `MethodChannel` / `FoundationModels` bridge, real auto-detection, real routing.
3. **AERO tab must DEFAULT in the aero tab** — it should NOT prompt "dumb shit" like `OLLAMA_HOST=0.0.0.0 ollama serve + ollama run llama3` or `set to http://192.168.1.15:11434` on every message.
4. It should **figure all the nuances itself**: device model, iOS version, model file exists, VPN status, time, SQLite brain.

**If you are Claude fixing this, ask:** "Would this work on iPhone 13 with Xfinity VPN ON and no Surface nearby?" If no, it's wrong.

---

## 2. PUSH 5 AERO Acceptance Criteria (What MUST Be True)

### AERO Tab Defaulting & Auto-Detection (THE MAIN BUG FIXED TODAY)

- [ ] **On app launch, AERO auto-detects engine in background** — no blocking dialog
  - Check `AERO/models/tinyllama-1.1b-chat.gguf` exists AND size >400MB → `hasModel=true`
  - Check Ollama `GET /api/tags` 3s timeout → `ollamaOnline`
  - Check Apple Intelligence via MethodChannel `com.onyxbeacon/aero` → `appleIntelligenceStatus` (FoundationModels, **iOS 26+**, iPhone 15 Pro / 16 / 17 series) → `appleAvailable`. iPhone 13 always reports `deviceNotEligible` — correct, it falls to TinyLlama/Core.
  - **Auto-pick (no prompt):**
    1. `hi/hello/hey`, `what time is it`, `summarize my week` → **Core** instant (works even with 0MB model)
    2. If `hasModel` → **Engine 1 TinyLlama** (ANY iPhone including iPhone 13, offline, VPN ON ok)
    3. Else if `appleAvailable` → **Engine 2 Apple Intelligence**
    4. Else if `ollamaOnline` → **Engine 3 Ollama** (Surface same Wi-Fi)
    5. Else → **Core** + small status chip, NOT a big orange banner

- [ ] **No dumb prompts** — Old behavior: every offline message said `AI Offline: Fix: OLLAMA_HOST...` or `iPhone: set to http://192.168.1.15:11434`. NEW: only show one-time small chip: `Core instant • download 600MB in settings for full offline Bible/lifestyle AI` with `[Download]` button. After download, chip shows `600MB on-device ready • VPN ON ok • offline`

- [ ] **Engine label in AppBar** — Must show current engine: `AERO Core • instant • offline` or `Engine 1 TinyLlama • 612MB • offline` etc. Not generic `AERO — Real AI + Bible`

- [ ] **Initial welcome message** must be engine-aware and iPhone-first: "Hi Caleb — AERO here, iPhone-first. I auto-detect: Core (instant) → TinyLlama 600MB (offline) → Apple Intelligence (15 Pro+) → Ollama (Surface). Core works now: try 'hi', 'what time is it', 'summarize my week'."

### Apple Intelligence Architecture — ACTUALLY FUNCTIONING

- [ ] **Not just text cards.** Create real functional architecture:
  - `AeroArchitectureService.getEngines()` returns list of `AeroEngineInfo` with id, name, subtitle, description, availability, icon, color
  - `AppleIntelligenceService.checkAvailability()` — real check via `device_info_plus` + MethodChannel to Swift `AeroAppleAI.swift` that calls `FoundationModels` availability on iOS 18+
  - `AppleIntelligenceService.generateWithAppleIntelligence(prompt)` — MethodChannel bridge, fallback to TinyLlama if unavailable
  - Settings dialog shows 4 engines with real status: green check if ready, grey if not, with size/online status
  - Architecture dialog (auto_awesome icon) explains: "Think of AERO like a car brand. AERO is name on dashboard, memory, SQLite brain. Engine that talks can be swapped"

- [x] **`ios/Runner/AeroAppleAI.swift`** — in Runner's Sources build phase (project.pbxproj), registered in `AppDelegate.didInitializeImplicitFlutterEngine`, channel `com.onyxbeacon/aero`. FoundationModels is weak-linked so iOS 18 testers don't crash. Needs **Xcode 26** in the GitHub workflow; with older Xcode it still builds and reports `sdkMissing`. (No App Group needed for this — App Group is only for the home-screen widget.)

### True Offline — 600MB Model

- [ ] **Download once, offline forever:** Model URL `https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf`, save to `Documents/AERO/models/tinyllama-1.1b-chat.gguf`, ~600MB Q4_K_M
- [ ] **Progress bar** during download, keep app open warning
- [ ] **Validation:** file size >400MB = valid, else show incomplete message
- [ ] **Delete button** when model exists
- [ ] **Works with Xfinity VPN ON** — because it's `File(path)` not `http://127.0.0.1:9339` which VPN blocks

### Fast Paths (Core) — Must Work Without Any Model

- [ ] `hi / hello / hey` → instant greeting with model size, time, Detroit, "SQLite brain"
- [ ] `what time is it / current time / what day is it` → `DateFormat('h:mm a, EEEE, MMM d, yyyy').format(DateTime.now())` + "(AERO Core — device local, 100% offline, Xfinity VPN ON ok)"
- [ ] `summarize my last 7 days / weekly summary` → queries SQLite: habit_completions last 7d, transactions last 7d (net calc), journal_entries last 7d, tasks completed

### Build Must Work on Windows (Builder) — fllama Fix

- [ ] **pubspec.yaml hooks must be:**
```yaml
fllama:
  git:
    url: https://github.com/Telosnex/fllama.git
    ref: 8969049d2b71f1aa353f11d4ce82367d15291c7b   # pinned: prebuilts match these sources
hooks:
  user_defines:
    fllama:
      native_build: auto   # ONLY auto | download | source are valid. "prebuilt" throws → "Building native assets failed"
                           # no web_build line: valid values are download | local; app doesn't target web
```
- [ ] Never use `ref: main` — main moves past its published prebuilts → "package sources differ" → 16-min source build.
- [ ] **Windows build fix steps must be documented:** Delete `C:\Users\%USERNAME%\AppData\Local\Pub\Cache\git\fllama-*`, `flutter clean`, `flutter pub get`
- [ ] No `Bad state: package sources differ...` error
- [ ] Windows build in ~30s, not 16min

---

## 3. Current File State (After Today's Fix — Assume Works)

- `lib/main.dart` (root `/main.dart` in this workspace): ~3700 lines, PUSH 5 iPhone First
  - `DatabaseHelper` v7: tables `habits`, `habit_completions`, `tasks`, `finance_categories`, `transactions`, `journal_entries` (adds status, word_count, order_index, color), `gallery_images`
  - `ExportService`: JSON, CSV, Encrypted AES-256 (.enc) with SHA256 key, HomeWidget update
  - `AiCopilotService`: Ollama http://localhost:11434 default, checkConnection, improveText, summarize/expand/critique
  - `AeroOnDeviceService`: checkModelExists, getModelSizeMB, downloadModel with progress, _coreFastPath (hi/time/weekly), generateOnDevice with fllamaChat (OpenAiRequest, numGpuLayers 25 iOS / 20 other, contextSize 2048, temp 0.4), deleteModel
  - `AeroArchitectureService` + `AppleIntelligenceService`: real engine list, Apple Intelligence check placeholder
  - `WeeklyReviewService`: PDF generation
  - `P2PSyncService`: local IP, HttpServer 8765
  - Tabs: Dashboard, Habits, Tasks, Finance, Writing Hub (Kanban + List toggle), AERO (new iPhone-first), Gallery, Settings

- `pubspec.yaml` v1.0.0+11: sdk ^3.13.5, deps: path, sqflite, sqflite_common_ffi, image_picker, speech_to_text, fl_chart, path_provider, share_plus, intl, csv, flutter_markdown_plus, encrypt, crypto, window_manager, system_tray, launch_at_startup, home_widget, http, pdf, printing, device_info_plus, fllama git main + hooks prebuilt/none

- `AeroAppleAI.swift` — Swift bridge for FoundationModels (exists in workspace root, needs to be moved to ios/Runner/)
- `OnyxBeaconWidgets.swift` — iOS WidgetKit
- `Info.plist`, `Runner.entitlements` — App Group group.onyxbeacon

---

## 4. Build Instructions — iPhone Primary

### Windows (Builder Only — NOT primary)
```powershell
cd C:\Users\djtwi\onyx_beacon
# ONE-TIME (critical): let Git check out paths longer than 260 chars.
# Without it Git silently skips 4 deep llama.cpp files inside the pub cache, fllama computes
# source key f677fcaa… instead of 38a971f2…, and the hook fails with
# "package sources differ from the sources of its web files" (proven by reproducing the key).
git config --global core.longpaths true
# FIX fllama cache: delete the checkout that is missing those 4 files
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Pub\Cache\git\fllama-*" -ErrorAction SilentlyContinue
flutter clean
flutter pub get
flutter run -d windows
# Should build in ~30s, not 16min, no Bad state error
# Check: Dashboard shows metrics, AERO tab shows "AERO Core • instant • offline" chip, not orange banner
```

### iPhone 13 (Minimum Supported — MUST Work)
```powershell
flutter run -d "Caleb's iPhone 13"
# Test fast paths WITHOUT model:
# Type "hi" → instant
# Type "what time is it" → instant Detroit time
# Type "summarize my week" → SQLite summary
# Go to AERO settings → Download 600MB → keep app open → progress bar → 100% → "612MB ready"
# After download, type "hi" again → "Engine 1 TinyLlama • 612MB • offline" chip
# Type "What does Romans 8:28 mean for Detroit life?" → should use TinyLlama offline, with Xfinity VPN ON
```

### iPhone 17 Pro Max (Primary Target)
```powershell
flutter run -d "iPhone 17 Pro Max"
# Same as iPhone 13, plus:
# First fllama inference takes 20-30s (model load), second is instant
# Test with VPN ON (Xfinity) — must still work because it's file-based
# Test Apple Intelligence: if iOS 18+ and Apple Intelligence enabled, settings should show "Available"
# Check architecture dialog (auto_awesome icon) shows 4 engines with real availability
```

---

## 5. What Claude Should Fix — Known Inconsistencies & Missed Criteria

**If you are Claude, fix these — do not break what works:**

### Critical Fixes Needed

1. **AERO tab defaulting logic** — Ensure `_autoDetectEngine()` runs on init AND on resume (didChangeAppLifecycleState). Currently only on init. Add WidgetsBindingObserver.

2. **Apple Intelligence Architecture — Make it REAL**
   - Currently `checkAppleIntelligenceAvailable()` returns false always. Implement real MethodChannel:
     - iOS Swift: `AeroAppleAI.swift` should check `if #available(iOS 18.0, *) { FoundationModels.Model.isAvailable }`
     - Dart: `MethodChannel('com.onyxbeacon/aero').invokeMethod('checkAppleIntelligence')`
   - Wire in `ios/Runner/AppDelegate.swift`

3. **fllamaChat timeout & retry** — First run on iPhone 17 Pro Max is slow, user sees blank. Add streaming tokens to UI (typewriter effect), not just waiting for completer. Show partial tokens as they arrive.

4. **Speech-to-text on Windows** — Currently shows SnackBar "Voice works on iPhone/Android". Should hide mic button on Windows entirely (Platform.isWindows ? SizedBox : mic button) to avoid dumb prompt.

5. **Database migration v7** — `color`, `status`, `word_count`, `order_index` columns added via ALTER TABLE. Ensure `getHabits()` returns color, and habit UI shows color dot. Currently dot exists but picker dialog to change color is missing — add color picker (15 colors palette).

6. **Writing Hub Kanban reordering** — `ReorderableListView` inside Column with `order_index` — ensure it persists after app restart. Currently may reset if `order_index` not updated correctly on move between columns.

7. **Weekly PDF path** — `Documents/OnyxBeacon/reports/` — ensure folder created via `Directory(...).create(recursive:true)` before write, else fails on fresh install.

8. **P2P Sync** — Currently manual IP entry. Should add mDNS auto-discovery using `multicast_dns` package (optional, but acceptance criteria says P2P Sync Prep — make it discoverable).

9. **HomeWidget App Group** — `group.onyxbeacon` must be enabled in both Runner and Widget extension entitlements, else `HomeWidget.saveWidgetData` fails silently. Document in README.

10. **Error handling in generateOnDevice** — Currently catches all and returns Core message. Should differentiate: file not found vs size invalid vs fllama init error vs timeout, and log to debugPrint for Xcode console.

### Inconsistencies to Clean

- `AiCopilotService.baseUrl` default `http://localhost:11434` — on iPhone this will never work (Surface is at `http://192.168.1.15:11434`). Should default to `http://192.168.1.15:11434` on iOS and `http://localhost:11434` on Windows, auto-detected via `getLocalIp()` subnet scan.
- `AeroOnDeviceService._modelFileName` = `tinyllama-1.1b-chat.gguf` but `modelPath` variable still called `_modelFileName` — rename to be consistent.
- `WritingStatus` enum has `Idea` default, but DB default is `'Idea'` string — ensure case matches exactly.
- `ExportService._updateHomeWidget()` called after every export, but also should be called after habit completion toggle for real-time widget.

### Missed Acceptance Criteria (Original Vision)

- [ ] **Siri Shortcuts Engine 4** — Not implemented at all. Should create `AeroIntents.swift` with App Intents: "Ask AERO to summarize my week" → triggers Engine 1 via Shortcuts. Document setup: Shortcuts app → Add Action → Onyx Beacon → Ask AERO.
- [ ] **Bible deep mode** — When prompt contains "bible/verse/scripture/psalm/romans/jesus", systemPrompt should include "Deep Bible knowledge, cross-references, original Greek/Hebrew when helpful, practical Detroit lifestyle application" — currently only in AERO, not in Ollama path. Add to Ollama path too.
- [ ] **Real time injection** — Every AI prompt must include `Real time ${DateFormat('yyyy-MM-dd HH:mm:ss EEEE').format(DateTime.now())} Detroit EST` — ensure it's in both TinyLlama and Ollama requests.
- [ ] **Encrypted backup restore** — `exportEncryptedBackup` exists, but `importEncryptedBackup` UI missing. Add in Settings → Restore Encrypted.

---

## 6. Testing Checklist for Claude (Must Pass on iPhone 13 + 17 Pro Max)

- [ ] Launch app → AERO tab → shows "AERO Core • instant • offline" chip, NOT orange banner
- [ ] Type "hi" → instant response <500ms, mentions SQLite brain, Detroit time
- [ ] Type "what time is it" → instant, format `h:mm a, EEEE, MMM d, yyyy`
- [ ] Type "summarize my last 7 days" → queries SQLite, shows completions, tx net, writing count
- [ ] Download 600MB → progress bar → 100% → chip changes to "612MB on-device ready • VPN ON ok • offline"
- [ ] With VPN ON (Xfinity) → type "What does Psalm 23 mean for anxiety in Detroit?" → works offline (not "AI Offline")
- [ ] Architecture dialog (auto_awesome icon) → shows 4 engines with real status (green/grey), not just static text
- [ ] Settings → Engine tiles show real size/online status
- [ ] Windows build → `Remove-Item ...fllama-*` → `flutter run -d windows` → builds in <60s, no Bad state error
- [ ] Habit toggle → widget data updates (if App Group enabled)

---

## 7. Files to Provide to Claude

- `lib/main.dart` (this workspace `/main.dart`) — PUSH 5 iPhone First (~3700 lines)
- `pubspec.yaml` — v1.0.0+11 with hooks prebuilt/none
- `AeroAppleAI.swift` — Swift bridge (needs wiring)
- `OnyxBeaconWidgets.swift` — WidgetKit
- `Info.plist`, `Runner.entitlements` — App Group
- This README

**Do NOT provide** old `main_PUSH3...`, `main_PUSH4...` files — they are deprecated.

---

## 8. How to Prompt Claude

Copy-paste this to Claude:

> "You are fixing Onyx Beacon PUSH 5 AERO iPhone First. Read README_PUSH5_IPHONE_FIRST_FINAL.md completely. iPhone 13 and 17 Pro Max are PRIMARY, Windows is only builder. AERO tab must auto-detect engine (Core instant → TinyLlama 600MB offline → Apple Intelligence → Ollama) with NO dumb prompts. Apple Intelligence Architecture must ACTUALLY FUNCTION via MethodChannel + FoundationModels, not just text. Fix the 10 critical fixes and 4 inconsistencies listed, keep what works. Ensure `flutter run -d windows` builds after deleting fllama cache, and iPhone fast paths (hi/time/weekly) work without any model. Provide updated lib/main.dart and pubspec.yaml and AeroAppleAI.swift wired."

---

## 9. Final Notes — Detroit

Caleb — 26 — Detroit, MI — Onyx Beacon Creator. Welcome back, Caleb.

PUSH 5 is Sovereign + True Offline. No cloud, no fees, your data stays on your iPhone. Windows Surface Pro is just the workbench.

If today worked, tomorrow we polish: Siri Shortcuts, mDNS, color picker, encrypted restore, streaming tokens.

— Thing 1 + Thing 2 + AERO — Detroit

