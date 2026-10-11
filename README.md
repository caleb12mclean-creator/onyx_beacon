# Onyx Beacon — Command Center
**Offline-first life OS • SQLite v5 • Flutter 3.13.5+ • Windows ARM64 + iOS**

Personal vault for Habits, Tasks, Finance Ledger, and Writing Studio. 100% offline, 100% yours. No cloud.

### Current Build: v5.3.1 — Phone Layout Fix
- AppBar: `Onyx Beacon — Command Center` with `FittedBox(scaleDown)` — scales on iPhone instead of truncating to `Command Ce...`
- Welcome: `Welcome back, Caleb.` (was Commander)
- Bottom Nav: `Command | Habits | Tasks | Finances | Writing Hub` — fixed `Financ s` break and `Writing Hub` 2-line wrap via `NavigationBarTheme(fontSize: 11, height: 72)`
- Global Search: `Global search: habits, tasks, finance, writing...` preserved, with `isDense` alignment fix
- 1834 lines, full formatting preserved — fixes `MSB8066 G297C951C` build error from compressed files

---

## ✨ Features (v5)

### 1. Command Dashboard
- Global search across habits, tasks, transactions, journal (SQLite LIKE query)
- Metric cards: Tracked, Active, Transactions, Drafts, DB status, Export ready
- Quick Export: Full vault JSON backup + share
- Counts live from DB

### 2. Habits — Streaks + Heatmap
- `habits` + `habit_completions` (unique habit_id + date)
- 🔥 Streak calculation (consecutive days, starts today or yesterday)
- 14-day heatmap with today highlighted (blue border)
- Mark Today toggle, edit/delete
- Export habits + completions JSON

### 3. Tasks — Search + Complete
- Search filter
- Checkbox complete, edit/delete inline
- Export JSON

### 4. Finance Ledger & Budget — v5 Core Upgrade
- `finance_categories` (Expense/Income) with CRUD
- `transactions` (title, amount, type, category, date)
- Search by title/category
- Date range picker filter + Chip display + Clear Filters
- Net Balance + Income/Expense summary cards
- **fl_chart 0.71.0**:
  - PieChart: Expenses by Category
  - BarChart: Monthly Net (Income - Expense)
- Toggle charts, manage categories dialog (TabBar: Expenses/Income)
- SegmentedButton for Expense/Income
- Export CSV (transactions) + JSON

### 5. Writing Hub & Micro-Journal
- Categories: Daily Reflection, Thought / Idea, Article, Short Story, Book Chapter, Screenplay
- Moods: ⚡ Creative, 🔥 Focused, ✨ Inspired, 😌 Calm, 🌧 Reflective, 🔋 Exhausted
- Search by title/content/mood
- Filter chips (All + categories)
- Full-screen editor with format/mood dropdowns
- Export Writing Hub JSON

### 6. Export Center
- JSON: habits, tasks, transactions, writing
- CSV: finance transactions
- Full Backup: `onyx_beacon_full_backup_YYYY-MM-DD_HH-mm.json` with all tables + version + timestamp
- Uses `path_provider` + `share_plus` XFile sharing (works Windows + iOS)

---

## 🛠 Tech Stack

- **Flutter 3.32+ / Dart ^3.13.5** (your BuildTools 17.14.41 — September 2026 ships Dart 3.13.x, so ^3.13.5 is valid)
- **Database**: sqflite ^2.3.0 + path ^1.8.3 — DB v5 with onCreate + onUpgrade (v2 tasks, v3 transactions, v4 categories/journal, v5 habit_completions)
- **Charts**: fl_chart ^0.71.0
- **Export**: path_provider ^2.1.6, share_plus ^10.1.4, intl ^0.20.3, csv ^6.0.0
- **State**: setState + async DB helper (no Riverpod/BLoC yet)
- **Platforms**: Windows ARM64 (primary dev), iOS (phone screenshot validation)

## 📁 Project Structure

```
lib/
  main.dart (1834 lines) — OnyxBeaconApp + DatabaseHelper v5 + ExportService + 5 tabs
    MainDashboardShell — NavigationBar (Command, Habits, Tasks, Finances, Writing Hub)
    DashboardHomeTab — globalSearch + MetricCard
    HabitsTab — streaks + heatmap
    TasksTab — search + checkbox
    FinanceTab — charts + filters + categories
    JournalTab — writing studio
pubspec.yaml — sdk: ^3.13.5, dependencies: sqflite, fl_chart, path_provider, share_plus, intl, csv
windows/ — runner + CMake (ARM64)
```

## 🔨 Build — Windows ARM64 Fix (Thing 2)

The `MSB8066 G297C951C Can't find ')' to match '('` error you hit is from **minified single-line widgets** (col 856). Fix:

1. Keep file formatting at 1000+ lines, not 500 lines compressed
2. `for (var tx in _filteredTransactions.where((t) => t['type'] == 'Expense'))` — the `))` at end is correct: one closes `where(`, one closes `for(`
3. Don't put multiple widgets on one line

### Commands (PowerShell vs CMD)

You are in CMD, not PowerShell — `Copy-Item` and `# comment` fail in CMD.

CMD:
```cmd
cd C:\Users\djtwi\onyx_beacon
flutter clean
flutter pub get
flutter run -d windows
```

PowerShell:
```powershell
cd C:\Users\djtwi\onyx_beacon
Copy-Item lib\main.dart lib\main_v4_backup.dart -Force
flutter clean; flutter pub get; flutter run -d windows
```

### Git Pushes

**PUSH 1 (done): v5** — 93c1488 — export, global search, fl_chart analytics, habit streaks + heatmap, DB v5
**PUSH 2 (this): v5.3.1** — phone layout fix + README
```powershell
git add README.md lib/main.dart
git commit -m "fix: v5.3.1 phone layout - FittedBox Command Center, Caleb greeting, nav font 11, keep 1834-line formatting"
git push origin main
```
**PUSH 3 (next): v6** — markdown preview, encrypted backup (.enc AES, not sqlcipher), system tray + auto-launch (window_manager, tray_manager, launch_at_startup)

## 🗄 Database Schema v5

```sql
habits (id, name)
habit_completions (id, habit_id FK CASCADE, completed_date UNIQUE habit_id+date)
tasks (id, title, isCompleted)
finance_categories (id, name, type)
transactions (id, title, amount, type, category, date)
journal_entries (id, title, content, category, mood, date)
```

## 📤 Export Format

Full backup JSON:
```json
{
  "exported_at": "2026-...",
  "version": 5,
  "tables": {
    "habits": [...],
    "habit_completions": [...],
    "tasks": [...],
    "finance_categories": [...],
    "transactions": [...],
    "journal_entries": [...]
  }
}
```

## 🚧 Roadmap to v6

- Markdown preview in Writing Hub (flutter_markdown)
- Encrypted backup .enc (AES, keep sqlcipher out — breaks BuildTools)
- System tray + auto-start for Windows
- Daily briefing widget
- Widgets: habit streak widget, finance net widget

---

Built by Caleb — Commander of Onyx Beacon.
