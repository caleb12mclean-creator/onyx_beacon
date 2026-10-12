# Onyx Beacon — Life Command Center

**Version:** 1.0.0+7 (2026-10-12)  
**Device:** iPhone 17 Pro Max (2026) — planning iPhone 18 Pro Max upgrade  
**Focus:** Real AI for personal projects + lifestyle, faith, VPN-friendly, $99/yr Apple Developer next iteration

---

## PUSH 4 — Copiable AERO + Accurate Time + Xfinity Fix

This push fixes the build you hit and makes phone actually usable with Xfinity.

**Build:**
- Added `import 'package:flutter/services.dart';` → fixes `Clipboard isn't defined` at 3254
- `const ClipboardData` → `ClipboardData` → fixes `Not a constant expression`
- `Text` → `SelectableText` — long-press to copy URLs

**Accurate time:**
- Now injects `2026-10-12 HH:mm EEEE Detroit EST` into every AI prompt
- Fixes `March 18 2023` hallucination you saw for `date?` / `what time is it?`

**Current build:** `lib/main.dart` 3477 lines, `pubspec.yaml` 1.0.0+7 with `fllama` git main.

---

## iPhone 17 Pro Max 2026 — Real Instructions (Xfinity VPN)

You had: **Xfinity VPN, Type Xfinity, Server 127.0.0.1:9339, Connect On Demand ON**

That's Xfinity Advanced Security local proxy — not a normal VPN. Generic "Allow LAN" toggles don't work. That is why you got `AI Offline: TimeoutException after 0:01:00` and why the old in-app instructions didn't work.

**Fix A — Surface Llama3 (when you want big brain):**
1. iPhone Settings → VPN → Xfinity VPN → turn **Connect On Demand OFF** (yours is ON in screenshot)
2. Then manually turn Xfinity VPN OFF, or Xfinity app → Internet → Advanced Security → OFF (deletes 127.0.0.1:9339 profile)
3. Surface: `ipconfig` → note Wi-Fi IPv4 (not always 192.168.1.15, it changes)
4. Onyx → AI Chat → gear → AERO URL = `http://YOUR_SURFACE_IP:11434` → Save & Test
5. Surface PowerShell: `$env:OLLAMA_HOST="0.0.0.0"; ollama serve` + `ollama run llama3`

**Fix B — Real AI for faith + projects WITH Xfinity VPN ON (recommended for daily):**
1. AI Chat → gear → you now see **ON-DEVICE REAL AI (VPN-friendly, offline Bible)** — this was missing in old builds
2. Tap **Download 600MB Model** — progress bar — ~2 min
3. After `✅ Model downloaded`, ask anything with VPN ON: `Explain Romans 8:28 Greek` or `Bible plan for anxiety` or `personal project plan for cybersecurity paper` — returns `[on-device real AI - VPN-friendly]`, no Surface, no WiFi needed

If you don't see Download button, you're on pre-3477 build — replace `lib/main.dart` with latest from this repo.

---

## Faith + Personal Projects + Lifestyle — Real AI

You said: thinking small vs real AI for BIBLE and lifestyle. This push makes chat Bible-aware.

**Auto-detects:** `bible`, `verse`, `scripture`, `psalm`, `romans`, `genesis`, `jesus`, `god`, `faith`, `prayer`

**System prompt:** `You are Onyx Beacon AERO Bible Scholar + Life Coach. Deep Bible knowledge, cross-references, Greek/Hebrew when helpful, practical Detroit lifestyle application. Real time 2026-10-12`

**Examples that work offline after download:**
- `Bible plan for anxiety` → 7-day plan with verses + journaling + habit tie-in
- `Explain Psalm 23 with Hebrew` → literal + context + application to finance/habits
- `Summarize my last 7 days with faith lens` → uses local DB (habits, transactions, journals) + scripture
- `Help with cybersecurity management paper outline` → personal project mode, uses your local notes

Fallback: Surface offline → auto tries on-device TinyLlama if downloaded, else shows tip to download.

---

## $99/yr Apple Developer — PUSH 5 Plan

Currently sideloaded. PUSH 5 assumes you enroll ($99/yr = $8.25/mo).

**What it unlocks for iPhone 17 Pro Max → 18 Pro Max:**
- TestFlight — push to your 17 Pro Max without cable, no more `flutter run -d ios` debug
- App Store Connect private distribution for Life Command Center
- Push Notifications — habit reminders, prayer reminders, encrypted sync alerts
- Background Modes — home_widget timeline refresh, VPN-aware reachability detection for Xfinity 127.0.0.1:9339
- App Groups + Keychain — secure storage for encrypted journal + faith notes (replaces `encrypt: ^5.0.3` plaintext keys)
- CloudKit private (optional, zero fees if private DB) — E2E encrypted sync Surface ↔ iPhone 17 → 18 upgrade

**Cost vs value:** $8.25/mo vs $20 ChatGPT + $15 Bible app + $10 habit tracker = $45/mo. Sovereign after.

**TODO for PUSH 5:**
- Enroll, bundle `com.calebmclean.onyxbeacon`, enable App Groups, Keychain, Background Modes
- Replace `home_widget` with WidgetKit iOS 20 lock screen widgets (verse of day, habit streak)
- Sign provisioning for 17 Pro Max, seamless restore to 18 Pro Max via iCloud backup

---

## Cybersecurity Management Master's — Applied to Onyx

Thesis-friendly features in PUSH 4:

**1. Zero-Trust Local-First:**
- Now: `baseUrl` hardcoded `192.168.1.15:11434` — no TLS, IP spoofable
- PUSH 5: mTLS Surface↔iPhone (self-signed cert pin), document Xfinity `127.0.0.1:9339` as local MITM proxy threat model — perfect for risk assessment paper

**2. Encryption at Rest:**
- Now: `encrypt` + `crypto` with keys in `getApplicationDocumentsDirectory`
- PUSH 5: iOS Keychain via `flutter_secure_storage` + Secure Enclave Face ID for Bible journal, Surface DPAPI via `win32`, map to NIST 800-53 SC-28

**3. Logging & Compliance:**
- Add table `security_events` (login, model download, VPN block 127.0.0.1:9339, prompt injection attempt)
- Capstone: Map Onyx to CIS Controls v8, produce SOC 2 Type I evidence (local-first = no vendor risk)

**4. Threat Intel Tab (idea for class):**
- New tab: `Xfinity VPN Analysis` — reads VPN config (type, server, Connect On Demand), flags `127.0.0.1` local proxy risk, recommends on-device fallback
- Presentation: "Consumer ISP VPN vs Local AI Availability"

---

## 2026 iPhone Integrations — Possibilities & Limitations

**iPhone 17 Pro Max (iOS 20, A19 Pro, 12GB RAM, 8-core Neural Engine) — NOW:**

Can do:
- Apple Intelligence + App Intents: expose `Summarize my week` + `Bible verse` as Siri shortcut
- Local Network privacy: `NSLocalNetworkUsageDescription` required — you must allow in Settings → Privacy & Security → Local Network → Onyx ON (was root cause of timeout besides VPN)
- On-device: TinyLlama 1.1B Q4 600MB works, but 17 Pro Max can run Llama 3.2 3B Q4 (2GB) or Phi-3 Mini 3.8B (2.2GB) smoothly — deeper faith exegesis
- Live Activities + Dynamic Island: show AI thinking progress during 60s Ollama call
- Journal Suggestions API: suggest faith journaling from locations/workouts

Can't do / Limits:
- Xfinity `127.0.0.1:9339` — app cannot programmatically disable VPN (Apple privacy). Must be manual in Xfinity app or Settings
- Background fllama — iOS kills after 30s — download must be foreground, generation chunked to 512 tokens
- No JIT — Metal only, larger models slower than Surface llama3 8B

**iPhone 18 Pro Max (expected late 2027, A20 Pro, 16GB RAM, 20-core Neural Engine, iOS 21) — PLANNING:**

- 16GB RAM → run Llama 3.1 8B Q4 (~4.5GB) fully on-device — no Surface needed for deep Bible scholar
- 2x Neural Engine tokens/sec — cross-ref <5s vs 15s now
- Rumored Apple FoundationModels on-device (GPT 4o-mini class) — could replace fllama, zero download in iOS 21
- Wi-Fi 7 + rotating private Wi-Fi address — hardcoded `192.168.1.15` breaks, need mDNS `onyx-beacon.local` (PUSH 5)
- Migration: App Groups + Keychain auto-migrates via iCloud if $99/yr enrolled, else encrypted local export

**Recommendation:** Stay on 17 Pro Max for PUSH 4-5 with 3B model, evaluate 18 Pro Max for 8B on-device capstone demo: "Sovereign AI Faith Study on 16GB Edge Device" — ties to cybersecurity + personal projects.

---

## Push to Phone

```powershell
cd C:\Users\djtwi\onyx_beacon
git add pubspec.yaml lib/main.dart README.md
git commit -m "PUSH 4.1: Xfinity 127.0.0.1:9339 accurate + Download 600MB real AI faith + iPhone 17 Pro Max 2026 + $99/yr + CySec"
git push
flutter clean; flutter pub get
flutter run -d windows
# iPhone 17 Pro Max: flutter run -d ios (or build ios --release for TestFlight after $99)
```

**Files:**
- `pubspec.yaml` — 1.0.0+7, fllama git main, uuid override
- `lib/main.dart` — 3477 lines, services import, no const ClipboardData, SelectableText, Xfinity Fix chip, Download 600MB with progress, Bible-aware, real time
- `README.md` — this file

---

## Checklist

- [ ] Replace lib/main.dart with 3477-line fixed (has `import services.dart`)
- [ ] `flutter clean; flutter pub get; flutter run -d windows` — no Clipboard error
- [ ] iPhone 17 Pro Max: Settings → Privacy → Local Network → Onyx ON
- [ ] AI Chat → gear → Download 600MB (or 2-3GB for deeper faith)
- [ ] Test with Xfinity VPN ON: `Explain Romans 8:28 Greek`
- [ ] Test with Xfinity VPN OFF + Surface: Save & Test `http://192.168.1.15:11434`
- [ ] Enroll $99/yr when ready for PUSH 5 TestFlight + WidgetKit
- [ ] Document Xfinity 127.0.0.1:9339 case for cybersecurity paper
