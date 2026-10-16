import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
// flame removed for fl_chart 1.2.0 / Windows build — using custom canvas games
// import 'package:flame/game.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' as crypto;
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' as pdfLib;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fllama/fllama.dart';
import 'package:device_info_plus/device_info_plus.dart';

Future<void> _initHomeWidget() async {
  try { await HomeWidget.setAppGroupId('group.onyxbeacon'); } catch(e){ debugPrint('HomeWidget: $e'); }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; }
  await _initHomeWidget();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions opts = const WindowOptions(size: Size(1280,800), center:true, backgroundColor: Colors.transparent, skipTaskbar:false, titleBarStyle: TitleBarStyle.normal, title: 'Onyx Beacon — Command Center');
      await windowManager.waitUntilReadyToShow(opts, () async { await windowManager.show(); await windowManager.focus(); });
    } catch(e){ debugPrint('Window: $e'); }
    // Tray is optional: it needs an absolute .ico path (a relative one gave "Bad Arguments").
    try {
      final icon = path.join(Directory.current.path, 'windows', 'runner', 'resources', 'app_icon.ico');
      if (Platform.isWindows && File(icon).existsSync()) {
        final tray = SystemTray();
        await tray.initSystemTray(title: "Onyx Beacon", iconPath: icon, toolTip: "Onyx Beacon — Command Center");
        final menu = Menu();
        await menu.buildFrom([MenuItemLabel(label: 'Show Onyx Beacon', onClicked: (_) async => await windowManager.show()), MenuSeparator(), MenuItemLabel(label: 'Quit', onClicked: (_) => exit(0))]);
        await tray.setContextMenu(menu);
        tray.registerSystemTrayEventHandler((e){ if(e==kSystemTrayEventClick) windowManager.show(); });
      }
    } catch(e){ debugPrint('Tray: $e'); }
    try {
      launchAtStartup.setup(appName: 'Onyx Beacon', appPath: Platform.resolvedExecutable);
    } catch(e){ debugPrint('Startup: $e'); }
  }
  runApp(const OnyxBeaconApp());
  // AERO picks its engine in the background — no dialog, no prompt.
  unawaited(AeroRouter.instance.detect(force: true));
}

class OnyxBeaconApp extends StatelessWidget {
  const OnyxBeaconApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onyx Beacon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A4E69),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          iconTheme: WidgetStateProperty.all(const IconThemeData(size: 22)),
          height: 72,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A4E69),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          iconTheme: WidgetStateProperty.all(const IconThemeData(size: 22)),
          height: 72,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainDashboardShell(),
    );
  }
}

// ==================== DATABASE HELPER v5 ====================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  // One shared Future: every widget that asks during startup waits on the SAME open,
  // instead of each opening its own connection (that raced 4x at launch).
  static Future<Database>? _dbFuture;

  DatabaseHelper._init();

  Future<Database> get database => _dbFuture ??= _initDB('onyx_beacon.db').catchError((Object e, StackTrace st) {
        // If opening failed, let the next caller retry instead of caching the error forever.
        _dbFuture = null;
        return Future<Database>.error(e, st);
      });

  Future<Database> _initDB(String filePath) async {
    String dbPath;
    if (Platform.isWindows || Platform.isLinux) {
      // main() already set databaseFactory = databaseFactoryFfi; setting it again only repeats the warning.
      dbPath = await databaseFactoryFfi.getDatabasesPath();
    } else {
      dbPath = await getDatabasesPath();
    }
    final dbP = path.join(dbPath, filePath);

    return await openDatabase(
      dbP,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#FF6B6B'
      )
    ''');
    await db.execute('''
      CREATE TABLE habit_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL,
        completed_date TEXT NOT NULL,
        FOREIGN KEY (habit_id) REFERENCES habits (id) ON DELETE CASCADE,
        UNIQUE(habit_id, completed_date)
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE finance_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        color TEXT DEFAULT '#4ECDC4'
      )
    ''');
    await db.execute('''
      CREATE TABLE gallery_images( id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT, name TEXT, created TEXT );
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT NOT NULL,
        mood TEXT NOT NULL,
        date TEXT NOT NULL,
        color TEXT DEFAULT '#9B59B6',
        status TEXT DEFAULT 'Idea',
        word_count INTEGER DEFAULT 0,
        order_index INTEGER DEFAULT 0
      )
    ''');

    final defaultCategories = [
      {'name': 'Housing & Rent', 'type': 'Expense'},
      {'name': 'Groceries', 'type': 'Expense'},
      {'name': 'Utilities', 'type': 'Expense'},
      {'name': 'Transport', 'type': 'Expense'},
      {'name': 'Dining Out', 'type': 'Expense'},
      {'name': 'Entertainment', 'type': 'Expense'},
      {'name': 'Salary', 'type': 'Income'},
      {'name': 'Freelance', 'type': 'Income'},
      {'name': 'Investments', 'type': 'Income'},
    ];
    for (var cat in defaultCategories) {
      await db.insert('finance_categories', cat);
    }
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          isCompleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          amount REAL NOT NULL,
          type TEXT NOT NULL,
          category TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS finance_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS journal_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          category TEXT NOT NULL,
          mood TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');
      await db.insert('finance_categories', {'name': 'Housing & Rent', 'type': 'Expense'});
      await db.insert('finance_categories', {'name': 'Groceries', 'type': 'Expense'});
      await db.insert('finance_categories', {'name': 'Salary', 'type': 'Income'});
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS habit_completions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          habit_id INTEGER NOT NULL,
          completed_date TEXT NOT NULL,
          FOREIGN KEY (habit_id) REFERENCES habits (id) ON DELETE CASCADE,
          UNIQUE(habit_id, completed_date)
        )
      ''');
    }
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE habits ADD COLUMN color TEXT DEFAULT "#FF6B6B"'); } catch (_) {}
      try { await db.execute('ALTER TABLE finance_categories ADD COLUMN color TEXT DEFAULT "#4ECDC4"'); } catch (_) {}
      try { await db.execute('ALTER TABLE journal_entries ADD COLUMN color TEXT DEFAULT "#9B59B6"'); } catch (_) {}
    }
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE journal_entries ADD COLUMN status TEXT DEFAULT "Idea"'); } catch (_) {}
      try { await db.execute('ALTER TABLE journal_entries ADD COLUMN word_count INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE journal_entries ADD COLUMN order_index INTEGER DEFAULT 0'); } catch (_) {}
    }
  }

  // --- Habits ---
  Future<List<Map<String, dynamic>>> getHabits() async {
    final db = await database;
    return await db.query('habits');
  }
  Future<int> insertHabit(String name, {String color = '#FF6B6B'}) async {
    final db = await database;
    return await db.insert('habits', {'name': name, 'color': color});
  }
  Future<int> updateHabit(int id, String name, {String? color}) async {
    final db = await database;
    return await db.update('habits', {'name': name, if (color != null) 'color': color}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteHabit(int id) async {
    final db = await database;
    await db.delete('habit_completions', where: 'habit_id = ?', whereArgs: [id]);
    return await db.delete('habits', where: 'id = ?', whereArgs: [id]);
  }

  // --- Habit Completions / Streaks ---
  Future<List<Map<String, dynamic>>> getHabitCompletions(int habitId) async {
    final db = await database;
    return await db.query('habit_completions', where: 'habit_id = ?', whereArgs: [habitId], orderBy: 'completed_date DESC');
  }
  Future<int> toggleHabitCompletion(int habitId, String date) async {
    final db = await database;
    final existing = await db.query('habit_completions', where: 'habit_id = ? AND completed_date = ?', whereArgs: [habitId, date]);
    if (existing.isNotEmpty) {
      final r = await db.delete('habit_completions', where: 'habit_id = ? AND completed_date = ?', whereArgs: [habitId, date]);
      unawaited(ExportService.updateHomeWidget());
      return r;
    } else {
      final r = await db.insert('habit_completions', {'habit_id': habitId, 'completed_date': date});
      unawaited(ExportService.updateHomeWidget());
      return r;
    }
  }
  Future<int> getHabitStreak(int habitId) async {
    final completions = await getHabitCompletions(habitId);
    if (completions.isEmpty) return 0;
    final dates = completions.map((e) => DateTime.parse(e['completed_date'] as String)).toList()..sort((a,b) => b.compareTo(a));
    int streak = 0;
    DateTime current = DateTime.now();
    // Normalize to date only
    current = DateTime(current.year, current.month, current.day);
    for (int i=0; i<dates.length; i++) {
      final d = DateTime(dates[i].year, dates[i].month, dates[i].day);
      final diff = current.difference(d).inDays;
      if (diff == streak || (streak==0 && diff <=1)) {
        streak++;
        current = d.subtract(const Duration(days: 1));
        // Actually need to check consecutive
        // Simpler: check if sorted list has consecutive days from today or yesterday
      } else {
        break;
      }
    }
    // More accurate streak calc:
    streak = 0;
    DateTime checkDate = DateTime.now();
    checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day);
    final dateSet = dates.map((e) => DateTime(e.year, e.month, e.day).toIso8601String().substring(0,10)).toSet();
    // Allow streak to start today or yesterday
    if (!dateSet.contains(checkDate.toIso8601String().substring(0,10))) {
      checkDate = checkDate.subtract(const Duration(days:1));
    }
    while (dateSet.contains(checkDate.toIso8601String().substring(0,10))) {
      streak++;
      checkDate = checkDate.subtract(const Duration(days:1));
    }
    return streak;
  }

  // --- Tasks ---
  Future<List<Map<String, dynamic>>> getTasks() async {
    final db = await database;
    return await db.query('tasks');
  }
  Future<int> insertTask(String title) async {
    final db = await database;
    return await db.insert('tasks', {'title': title, 'isCompleted': 0});
  }
  Future<int> updateTaskTitle(int id, String title) async {
    final db = await database;
    return await db.update('tasks', {'title': title}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> updateTaskCompletion(int id, int isCompleted) async {
    final db = await database;
    final r = await db.update('tasks', {'isCompleted': isCompleted}, where: 'id = ?', whereArgs: [id]);
    unawaited(ExportService.updateHomeWidget());
    return r;
  }
  Future<int> deleteTask(int id) async {
    final db = await database;
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // --- Finance Categories ---
  Future<List<Map<String, dynamic>>> getFinanceCategories(String type) async {
    final db = await database;
    return await db.query('finance_categories', where: 'type = ?', whereArgs: [type]);
  }
  Future<List<Map<String, dynamic>>> getAllFinanceCategories() async {
    final db = await database;
    return await db.query('finance_categories');
  }
  Future<int> insertFinanceCategory(String name, String type) async {
    final db = await database;
    return await db.insert('finance_categories', {'name': name, 'type': type});
  }
  Future<int> updateFinanceCategory(int id, String name) async {
    final db = await database;
    return await db.update('finance_categories', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteFinanceCategory(int id) async {
    final db = await database;
    return await db.delete('finance_categories', where: 'id = ?', whereArgs: [id]);
  }

  // --- Transactions ---
  Future<List<Map<String, dynamic>>> getTransactions() async {
    final db = await database;
    return await db.query('transactions', orderBy: 'date DESC, id DESC');
  }
  Future<int> insertTransaction(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('transactions', row);
  }
  Future<int> updateTransaction(int id, Map<String, dynamic> row) async {
    final db = await database;
    return await db.update('transactions', row, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- Journal ---
  Future<List<Map<String, dynamic>>> getJournalEntries() async {
    final db = await database;
    return await db.query('journal_entries', orderBy: 'id DESC');
  }
  Future<int> insertJournalEntry(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('journal_entries', row);
  }
  Future<int> updateJournalEntry(int id, Map<String, dynamic> row) async {
    final db = await database;
    return await db.update('journal_entries', row, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteJournalEntry(int id) async {
    final db = await database;
    return await db.delete('journal_entries', where: 'id = ?', whereArgs: [id]);
  }

  // --- Global Search ---
  Future<Map<String, List<Map<String, dynamic>>>> globalSearch(String query) async {
    if (query.trim().isEmpty) return {'habits': [], 'tasks': [], 'transactions': [], 'journal': []};
    final db = await database;
    final q = '%${query.trim()}%';
    final habits = await db.query('habits', where: 'name LIKE ?', whereArgs: [q]);
    final tasks = await db.query('tasks', where: 'title LIKE ?', whereArgs: [q]);
    final txs = await db.query('transactions', where: 'title LIKE ? OR category LIKE ?', whereArgs: [q, q]);
    final journals = await db.query('journal_entries', where: 'title LIKE ? OR content LIKE ? OR category LIKE ?', whereArgs: [q, q, q]);
    return {'habits': habits, 'tasks': tasks, 'transactions': txs, 'journal': journals};
  }

  // --- Export Helpers ---
  Future<List<Map<String, dynamic>>> getAllDataForExport() async {
    final db = await database;
    final habits = await db.query('habits');
    final completions = await db.query('habit_completions');
    final tasks = await db.query('tasks');
    final categories = await db.query('finance_categories');
    final txs = await db.query('transactions');
    final journals = await db.query('journal_entries');
    return [
      {'table': 'habits', 'data': habits},
      {'table': 'habit_completions', 'data': completions},
      {'table': 'tasks', 'data': tasks},
      {'table': 'finance_categories', 'data': categories},
      {'table': 'transactions', 'data': txs},
      {'table': 'journal_entries', 'data': journals},
    ];
  }
}

// ==================== EXPORT UTILITY + ENCRYPTED + WIDGETS ====================
class ExportService {
  static Future<void> exportJson(String fileName, dynamic data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, fileName));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      await Share.shareXFiles([XFile(file.path)], text: 'Onyx Beacon Export: $fileName');
    } catch (e) { debugPrint('Export JSON error: $e'); }
  }
  static Future<void> exportTransactionsCsv(List<Map<String, dynamic>> txs) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'transactions_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      final file = File(path.join(dir.path, fileName));
      final buffer = StringBuffer();
      buffer.writeln('id,title,amount,type,category,date');
      for (var tx in txs) { buffer.writeln('${tx['id']},"${tx['title']}",${tx['amount']},${tx['type']},${tx['category']},${tx['date']}'); }
      await file.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Onyx Beacon Finance CSV');
    } catch (e) { debugPrint('Export CSV error: $e'); }
  }
  static Future<void> exportJournalJson(List<Map<String, dynamic>> entries) async {
    final fileName = 'writing_hub_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    await exportJson(fileName, entries);
  }
  static Future<void> exportFullBackup() async {
    final allData = await DatabaseHelper.instance.getAllDataForExport();
    final Map<String, dynamic> backup = {'exported_at': DateTime.now().toIso8601String(), 'version': 7, 'tables': {for (var t in allData) t['table'] as String: t['data']}};
    final fileName = 'onyx_beacon_full_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
    await exportJson(fileName, backup);
    await _updateHomeWidget();
  }
  static Future<void> exportEncryptedBackup(String password) async {
    try {
      final allData = await DatabaseHelper.instance.getAllDataForExport();
      final backup = {'exported_at': DateTime.now().toIso8601String(), 'version': 7, 'encrypted': true, 'tables': {for (var t in allData) t['table'] as String: t['data']}};
      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);
      final keyBytes = crypto.sha256.convert(utf8.encode(password)).bytes;
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(jsonStr, iv: iv);
      final combined = base64Encode(iv.bytes + encrypted.bytes);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'onyx_beacon_ENCRYPTED_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.enc';
      final file = File(path.join(dir.path, fileName));
      await file.writeAsString(combined);
      await Share.shareXFiles([XFile(file.path)], text: 'Encrypted Backup: $fileName');
    } catch (e) { debugPrint('Encrypted error: $e'); }
  }
  static Future<void> updateHomeWidget() => _updateHomeWidget();
  static Future<void> _updateHomeWidget() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final habits = await db.query('habits');
      final completions = await db.query('habit_completions', where: 'completed_date = ?', whereArgs: [today]);
      final tasks = await db.query('tasks', where: 'isCompleted = 0');
      final txs = await db.query('transactions', where: 'date = ?', whereArgs: [today]);
      double net = 0;
      for (var t in txs) { final amt = (t['amount'] as num).toDouble(); net += t['type'] == 'Income' ? amt : -amt; }
      await HomeWidget.saveWidgetData('habits_due', habits.length - completions.length);
      await HomeWidget.saveWidgetData('tasks_pending', tasks.length);
      await HomeWidget.saveWidgetData('net_today', net.toStringAsFixed(2));
      await HomeWidget.saveWidgetData('last_updated', DateFormat('HH:mm').format(DateTime.now()));
      await HomeWidget.updateWidget(iOSName: 'OnyxBeaconWidgets', androidName: 'OnyxBeaconWidgetProvider');
    } catch (e) { debugPrint('Widget update error: $e'); }
  }
}


// ==================== PUSH 4 SOVEREIGN SERVICES ====================
// Writing Status Enum
enum WritingStatus { Idea, Drafting, Revision, Complete }
extension WritingStatusExt on WritingStatus {
  String get label => toString().split('.').last;
  Color get color {
    switch(this){
      case WritingStatus.Idea: return const Color(0xFFFFEAA7);
      case WritingStatus.Drafting: return const Color(0xFF45B7D1);
      case WritingStatus.Revision: return const Color(0xFFFF6B6B);
      case WritingStatus.Complete: return const Color(0xFF96CEB4);
    }
  }
  IconData get icon {
    switch(this){
      case WritingStatus.Idea: return Icons.lightbulb_outline;
      case WritingStatus.Drafting: return Icons.edit_outlined;
      case WritingStatus.Revision: return Icons.auto_fix_high_outlined;
      case WritingStatus.Complete: return Icons.check_circle_outline;
    }
  }
  static WritingStatus fromString(String s){
    switch(s){
      case 'Drafting': return WritingStatus.Drafting;
      case 'Revision': return WritingStatus.Revision;
      case 'Complete': return WritingStatus.Complete;
      default: return WritingStatus.Idea;
    }
  }
}


// ==================== AERO — 4-ENGINE ARCHITECTURE (iPhone first) ====================
// AERO is the brand on the dashboard + the SQLite brain. The engine that talks is swappable:
//   Core (always, instant, no model) → Engine 1 TinyLlama (on-device file, offline, VPN-proof)
//   → Engine 2 Apple Intelligence (FoundationModels via MethodChannel) → Engine 3 Ollama (Surface, same Wi-Fi)
// AeroRouter detects what exists, picks automatically, falls through on failure, and never nags.

enum AeroEngine { core, tinyllama, apple, ollama }

extension AeroEngineExt on AeroEngine {
  String get shortName {
    switch (this) {
      case AeroEngine.core: return 'AERO Core';
      case AeroEngine.tinyllama: return 'TinyLlama';
      case AeroEngine.apple: return 'Apple Intelligence';
      case AeroEngine.ollama: return 'Ollama';
    }
  }
  IconData get icon {
    switch (this) {
      case AeroEngine.core: return Icons.memory;
      case AeroEngine.tinyllama: return Icons.phone_iphone;
      case AeroEngine.apple: return Icons.auto_awesome;
      case AeroEngine.ollama: return Icons.computer;
    }
  }
  Color get color {
    switch (this) {
      case AeroEngine.core: return Colors.blueGrey;
      case AeroEngine.tinyllama: return Colors.green;
      case AeroEngine.apple: return Colors.deepPurple;
      case AeroEngine.ollama: return Colors.orange;
    }
  }
}

/// Typed failure so the router can fall back and log the real reason to the Xcode console.
enum AeroErrorKind { modelMissing, modelIncomplete, initFailed, timeout, empty, unavailable, network, unknown }

class AeroException implements Exception {
  final AeroErrorKind kind;
  final String message;
  AeroException(this.kind, this.message);
  @override
  String toString() => 'AeroException(${kind.name}): $message';
}

class AeroReply {
  final String text;
  final AeroEngine engine;
  final String? note;
  AeroReply(this.text, this.engine, {this.note});
}

class AeroMessage {
  final bool isUser;
  String text;
  AeroEngine? engine;
  bool streaming;
  String? note;
  AeroMessage({required this.isUser, required this.text, this.engine, this.streaming = false, this.note});
}

// --- Prompts: real time + Bible deep mode, shared by every engine ---
class AeroPrompts {
  static String realTime() => DateFormat('yyyy-MM-dd HH:mm:ss EEEE').format(DateTime.now());

  static final RegExp _verseRef = RegExp(r'\b(?:[1-3]\s?)?(?:gen|genesis|exod|exodus|lev|num|deut|josh|judg|ruth|sam|samuel|kings|chron|ezra|neh|esther|job|ps|psalms?|prov|proverbs|eccl|song|isa|isaiah|jer|lam|ezek|dan|hos|joel|amos|obad|jonah|mic|nah|hab|zeph|hag|zech|mal|matt|matthew|mark|luke|john|acts|rom|romans|cor|corinthians|gal|eph|phil|col|thess|tim|titus|philem|heb|james|pet|peter|jude|rev)\.?\s\d{1,3}:\d{1,3}\b');
  static const List<String> _bibleWords = [
    'bible', 'verse', 'scripture', 'psalm', 'proverb', 'romans', 'genesis', 'exodus', 'gospel',
    'jesus', 'christ', 'god', 'faith', 'pray', 'prayer', 'holy spirit', 'apostle', 'corinthians',
    'ephesians', 'philippians', 'hebrews', 'isaiah', 'revelation', 'matthew', 'luke',
  ];

  static bool isBible(String text) {
    final l = text.toLowerCase();
    return _bibleWords.any(l.contains) || _verseRef.hasMatch(l);
  }

  static String system(String userText, {bool short = true}) {
    final now = realTime();
    final limit = short ? ' Keep answers under 150 words unless asked for more.' : '';
    if (isBible(userText)) {
      return 'You are AERO, Bible scholar and life coach inside Onyx Beacon for Caleb in Detroit. '
          'Real time: $now (America/Detroit). Deep Bible knowledge: give book chapter:verse, '
          'cross-references, original Greek/Hebrew when it helps, and practical Detroit lifestyle application. '
          'Never invent verses; say so if unsure. Never guess the date — use the real time given.$limit';
    }
    return 'You are AERO, the private on-device assistant inside Onyx Beacon (habits, tasks, finance, writing) '
        'for Caleb in Detroit. Real time: $now (America/Detroit). Be accurate, concise and practical. '
        'Never guess the date — use the real time given.$limit';
  }
}

// --- Persisted AERO settings (Ollama endpoint) — survives restarts, no extra package ---
class AeroSettings {
  static String ollamaUrl = (Platform.isIOS || Platform.isAndroid) ? 'http://192.168.1.15:11434' : 'http://localhost:11434';
  static String ollamaModel = 'llama3';
  static bool _loaded = false;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final aeroDir = Directory(path.join(dir.path, 'AERO'));
    if (!await aeroDir.exists()) await aeroDir.create(recursive: true);
    return File(path.join(aeroDir.path, 'settings.json'));
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      ollamaUrl = (data['ollamaUrl'] as String?)?.trim().isNotEmpty == true ? data['ollamaUrl'] as String : ollamaUrl;
      ollamaModel = (data['ollamaModel'] as String?)?.trim().isNotEmpty == true ? data['ollamaModel'] as String : ollamaModel;
    } catch (e) {
      debugPrint('[AERO] settings load failed: $e');
    }
  }

  static Future<void> save({required String url, required String model}) async {
    ollamaUrl = url.trim().isEmpty ? ollamaUrl : url.trim();
    ollamaModel = model.trim().isEmpty ? ollamaModel : model.trim();
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({'ollamaUrl': ollamaUrl, 'ollamaModel': ollamaModel}));
    } catch (e) {
      debugPrint('[AERO] settings save failed: $e');
    }
  }
}

// --- Engine 3: Ollama (Surface on same Wi-Fi, or localhost on Windows) ---
class AiCopilotService {
  static String get baseUrl => AeroSettings.ollamaUrl;
  static String get model => AeroSettings.ollamaModel;

  static Future<bool> checkConnection() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/tags')).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Throws [AeroException] on any failure so the router can fall back silently.
  static Future<String> chat(String userText, {String? system}) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'stream': false,
              'messages': [
                {'role': 'system', 'content': system ?? AeroPrompts.system(userText, short: false)},
                {'role': 'user', 'content': userText},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw AeroException(AeroErrorKind.timeout, 'Ollama did not answer in 90s');
    } catch (e) {
      throw AeroException(AeroErrorKind.network, 'Ollama unreachable at $baseUrl ($e)');
    }
    if (res.statusCode == 404) {
      throw AeroException(AeroErrorKind.unavailable, 'Model "$model" not found on $baseUrl');
    }
    if (res.statusCode != 200) {
      throw AeroException(AeroErrorKind.unknown, 'Ollama HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    final text = (data['message']?['content'] ?? '').toString().trim();
    if (text.isEmpty) throw AeroException(AeroErrorKind.empty, 'Ollama returned an empty answer');
    return text;
  }
}

// --- Engine 2: Apple Intelligence (FoundationModels, iOS 26+, iPhone 15 Pro and newer) ---
class AppleIntelligenceService {
  static const MethodChannel _channel = MethodChannel('com.onyxbeacon/aero');

  /// available | deviceNotEligible | appleIntelligenceNotEnabled | modelNotReady | osTooOld | sdkMissing | notIOS | bridgeMissing | error
  static String status = 'unknown';

  static Future<bool> checkAvailability() async {
    if (!Platform.isIOS) {
      status = 'notIOS';
      return false;
    }
    try {
      status = await _channel.invokeMethod<String>('appleIntelligenceStatus') ?? 'error';
    } on MissingPluginException {
      status = 'bridgeMissing';
    } catch (e) {
      debugPrint('[AERO] Apple Intelligence status check failed: $e');
      status = 'error';
    }
    return status == 'available';
  }

  static String get statusLabel {
    switch (status) {
      case 'available': return 'Ready — on-device, private';
      case 'deviceNotEligible': return 'This iPhone is not eligible (needs 15 Pro / 16 / 17 series)';
      case 'appleIntelligenceNotEnabled': return 'Turn on in Settings → Apple Intelligence & Siri';
      case 'modelNotReady': return 'Apple is still downloading its model — try later';
      case 'osTooOld': return 'Needs iOS 26 or newer';
      case 'sdkMissing': return 'App was built without the iOS 26 SDK (use Xcode 26 in CI)';
      case 'bridgeMissing': return 'Native bridge not registered in this build';
      case 'notIOS': return 'iPhone only';
      default: return 'Checking…';
    }
  }

  static Future<String> generateWithAppleIntelligence(String prompt, {String? instructions}) async {
    try {
      final text = await _channel.invokeMethod<String>('generate', {
        'prompt': prompt,
        'instructions': instructions ?? AeroPrompts.system(prompt),
      });
      if (text == null || text.trim().isEmpty) {
        throw AeroException(AeroErrorKind.empty, 'Apple Intelligence returned an empty answer');
      }
      return text.trim();
    } on PlatformException catch (e) {
      throw AeroException(
        e.code == 'UNAVAILABLE' ? AeroErrorKind.unavailable : AeroErrorKind.unknown,
        'Apple Intelligence: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      throw AeroException(AeroErrorKind.unavailable, 'Apple Intelligence bridge missing');
    }
  }
}

// --- Engine 1 + Core: on-device TinyLlama (works with VPN ON — it's a file, not a network call) ---
class AeroOnDeviceService {
  static const String modelFileName = 'tinyllama-1.1b-chat.gguf';
  static const String modelUrl =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';
  static const int minValidBytes = 400 * 1024 * 1024;

  /// null = idle, 0..1 = downloading. UI listens to this from anywhere (chip, settings).
  static final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  static bool get isDownloading => downloadProgress.value != null;
  static bool _warmedUp = false;
  static String? _modelPath;

  static Future<String> getModelPath() async {
    if (_modelPath != null) return _modelPath!;
    final dir = await getApplicationDocumentsDirectory();
    final aeroDir = Directory(path.join(dir.path, 'AERO', 'models'));
    if (!await aeroDir.exists()) await aeroDir.create(recursive: true);
    _modelPath = path.join(aeroDir.path, modelFileName);
    return _modelPath!;
  }

  static Future<bool> checkModelExists() async {
    try {
      final f = File(await getModelPath());
      return await f.exists() && await f.length() > minValidBytes;
    } catch (_) {
      return false;
    }
  }

  static Future<int> getModelSizeMB() async {
    try {
      final f = File(await getModelPath());
      if (!await f.exists()) return 0;
      return await f.length() ~/ (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }

  /// Downloads to a .part file and only renames it when complete, so a killed download never looks valid.
  static Future<bool> downloadModel() async {
    if (isDownloading) return false;
    downloadProgress.value = 0;
    final client = http.Client();
    File? part;
    try {
      final savePath = await getModelPath();
      part = File('$savePath.part');
      if (await part.exists()) await part.delete();
      final streamed = await client.send(http.Request('GET', Uri.parse(modelUrl)));
      if (streamed.statusCode != 200) {
        throw AeroException(AeroErrorKind.network, 'Download HTTP ${streamed.statusCode}');
      }
      final total = streamed.contentLength ?? 0;
      int received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in streamed.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) downloadProgress.value = received / total;
        }
      } finally {
        await sink.close();
      }
      if ((total > 0 && received != total) || received < minValidBytes) {
        throw AeroException(AeroErrorKind.modelIncomplete, 'Got ${received ~/ (1024 * 1024)} MB of ${total ~/ (1024 * 1024)} MB');
      }
      final finalFile = File(savePath);
      if (await finalFile.exists()) await finalFile.delete();
      await part.rename(savePath);
      _warmedUp = false;
      return true;
    } catch (e) {
      debugPrint('[AERO] model download failed: $e');
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close();
      downloadProgress.value = null;
    }
  }

  static Future<void> deleteModel() async {
    try {
      final f = File(await getModelPath());
      if (await f.exists()) await f.delete();
      _warmedUp = false;
    } catch (e) {
      debugPrint('[AERO] delete model failed: $e');
    }
  }

  static String _clock() => DateFormat('h:mm a, EEEE, MMM d, yyyy').format(DateTime.now());

  static String _norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[!?.,]+$'), '').trim();

  /// CORE — instant answers straight from the SQLite brain. Works on every device with no model and no network.
  static Future<String?> coreFastPath(String prompt, {String engineLine = ''}) async {
    final lower = _norm(prompt);
    final timeStr = _clock();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    const greetings = {'hi', 'hello', 'hey', 'yo', 'hi aero', 'hey aero', 'hello aero', 'good morning', 'good afternoon', 'good evening'};

    if (greetings.contains(lower)) {
      int due = 0, pending = 0;
      try {
        final db = await DatabaseHelper.instance.database;
        final habits = await db.query('habits');
        final done = await db.query('habit_completions', where: 'completed_date = ?', whereArgs: [today]);
        final doneIds = done.map((e) => e['habit_id']).toSet();
        due = habits.where((h) => !doneIds.contains(h['id'])).length;
        pending = (await db.query('tasks', where: 'isCompleted = 0')).length;
      } catch (_) {}
      final line = engineLine.isEmpty ? '' : ' Talking through $engineLine.';
      return 'Hi Caleb — AERO here.$line It\'s $timeStr in Detroit. '
          'From your SQLite brain: $due habit${due == 1 ? '' : 's'} left today, $pending task${pending == 1 ? '' : 's'} pending.';
    }

    if (lower.contains('what time') || lower.contains('current time') || lower == 'time' ||
        lower.contains('what day is it') || lower.contains("what's the date") || lower.contains('what is the date') ||
        lower.contains("today's date")) {
      return 'Current time: $timeStr (AERO Core — device local, 100% offline, VPN ON ok).';
    }

    if (lower.contains('summarize my last 7 days') || lower.contains('summarize my week') ||
        lower.contains('weekly summary') || lower.contains('last 7 days') || lower == 'my week') {
      try {
        final db = await DatabaseHelper.instance.database;
        final weekAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)));
        final comps = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [weekAgo]);
        final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [weekAgo]);
        final journals = await db.query('journal_entries', where: 'date >= ?', whereArgs: [weekAgo]);
        final doneTasks = await db.query('tasks', where: 'isCompleted = 1');
        final openTasks = await db.query('tasks', where: 'isCompleted = 0');
        double net = 0;
        for (final t in txs) {
          final amt = (t['amount'] as num).toDouble();
          net += t['type'] == 'Income' ? amt : -amt;
        }
        int words = 0;
        for (final j in journals) {
          words += (j['content'] as String).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        }
        return 'Last 7 days (AERO Core, offline):\n'
            '• Habits: ${comps.length} completions\n'
            '• Finance: ${txs.length} transactions, net \$${net.toStringAsFixed(2)}\n'
            '• Writing: ${journals.length} entries, $words words\n'
            '• Tasks: ${doneTasks.length} done, ${openTasks.length} open\n'
            '($timeStr)';
      } catch (e) {
        return 'Couldn\'t read your week from SQLite: $e';
      }
    }

    // The next shortcuts only fire for short, non-Bible questions so real questions reach the model.
    if (AeroPrompts.isBible(prompt) || lower.length > 60) return null;

    if (lower.contains('habit') && (lower.contains('today') || lower.contains('due') || lower.contains('left'))) {
      try {
        final db = await DatabaseHelper.instance.database;
        final habits = await db.query('habits');
        final done = await db.query('habit_completions', where: 'completed_date = ?', whereArgs: [today]);
        final doneIds = done.map((e) => e['habit_id']).toSet();
        final due = habits.where((h) => !doneIds.contains(h['id'])).map((h) => '• ${h['name']}').toList();
        return due.isEmpty ? 'Every habit is done today. 🔥' : 'Habits left today:\n${due.join('\n')}';
      } catch (_) {}
    }

    if (lower.contains('my tasks') || lower.contains('todo') || lower.contains('to do') ||
        lower.contains('pending tasks') || lower.contains("what's on my list")) {
      try {
        final db = await DatabaseHelper.instance.database;
        final open = await db.query('tasks', where: 'isCompleted = 0', limit: 12);
        return open.isEmpty ? 'No pending tasks. 🎉' : 'Pending tasks:\n${open.map((t) => '• ${t['title']}').join('\n')}';
      } catch (_) {}
    }

    if (lower.contains('spent') || lower.contains('spending') || lower.contains('balance') || lower.contains('budget')) {
      try {
        final db = await DatabaseHelper.instance.database;
        final monthStart = DateFormat('yyyy-MM-01').format(DateTime.now());
        final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [monthStart]);
        double inc = 0, exp = 0;
        for (final t in txs) {
          final amt = (t['amount'] as num).toDouble();
          if (t['type'] == 'Income') { inc += amt; } else { exp += amt; }
        }
        return 'This month: income \$${inc.toStringAsFixed(2)}, spent \$${exp.toStringAsFixed(2)}, net \$${(inc - exp).toStringAsFixed(2)} (${txs.length} transactions).';
      } catch (_) {}
    }

    if (lower == 'help' || lower.contains('what can you do')) {
      return 'Instant (no model): "hi", "what time is it", "summarize my week", "habits left today", "my tasks", "how much have I spent".\n'
          'Everything else — Bible study, writing help, planning — goes to the best engine on this phone.';
    }
    return null;
  }

  /// Engine 1 — streams cumulative text through [onPartial]. Throws [AeroException] with the real failure kind.
  static Future<String> generateOnDevice(String prompt, {void Function(String partial)? onPartial}) async {
    final modelPath = await getModelPath();
    final file = File(modelPath);
    if (!await file.exists()) throw AeroException(AeroErrorKind.modelMissing, 'No model file at $modelPath');
    final size = await file.length();
    if (size < minValidBytes) {
      throw AeroException(AeroErrorKind.modelIncomplete, 'Model is only ${size ~/ (1024 * 1024)} MB');
    }

    final request = OpenAiRequest(
      maxTokens: 400,
      messages: [
        Message(Role.system, AeroPrompts.system(prompt)),
        Message(Role.user, prompt),
      ],
      numGpuLayers: (Platform.isIOS || Platform.isMacOS) ? 99 : 0,
      modelPath: modelPath,
      contextSize: 2048,
      temperature: 0.4,
      topP: 0.9,
    );

    final completer = Completer<String>();
    String latest = '';
    int? requestId;
    try {
      requestId = await fllamaChat(request, (String response, String openAiJson, bool done) {
        if (completer.isCompleted) return;
        if (done && response.startsWith('Error:')) {
          completer.completeError(AeroException(AeroErrorKind.initFailed, response));
          return;
        }
        if (response.isNotEmpty) {
          latest = response;
          onPartial?.call(latest);
        }
        if (done) completer.complete(latest);
      });
    } catch (e) {
      throw AeroException(AeroErrorKind.initFailed, 'fllama could not start: $e');
    }

    // First load on a cold phone reads ~640 MB into memory; give it time, then stream.
    final limit = _warmedUp ? const Duration(seconds: 60) : const Duration(seconds: 120);
    try {
      final result = await completer.future.timeout(limit);
      _warmedUp = true;
      if (result.trim().isEmpty) throw AeroException(AeroErrorKind.empty, 'TinyLlama returned an empty answer');
      return result.trim();
    } on TimeoutException {
      if (requestId != null) fllamaCancelInference(requestId);
      if (latest.trim().isNotEmpty) {
        _warmedUp = true;
        return '${latest.trim()}\n\n[stopped after ${limit.inSeconds}s]';
      }
      throw AeroException(AeroErrorKind.timeout, 'No tokens after ${limit.inSeconds}s');
    }
  }
}

// --- Engine catalogue for the architecture + settings dialogs (live status, not static text) ---
class AeroEngineInfo {
  final AeroEngine id;
  final String name;
  final String subtitle;
  final String description;
  final String availability;
  final bool ready;
  final bool active;
  AeroEngineInfo({required this.id, required this.name, required this.subtitle, required this.description,
      required this.availability, required this.ready, required this.active});
  IconData get icon => id.icon;
  Color get color => id.color;
}

class AeroArchitectureService {
  static List<AeroEngineInfo> getEngines(AeroRouter r) {
    final primary = r.primary;
    return [
      AeroEngineInfo(
        id: AeroEngine.core, name: 'Core', subtitle: 'Always on • instant',
        description: 'Greetings, time, weekly summary, habits left, tasks, spending — straight from SQLite. No model, no network.',
        availability: 'Ready', ready: true, active: primary == AeroEngine.core,
      ),
      AeroEngineInfo(
        id: AeroEngine.tinyllama, name: 'Engine 1 — TinyLlama', subtitle: 'Any iPhone • offline • VPN-proof',
        description: '1.1B chat model stored on the phone. Downloaded once (~640 MB), then works in airplane mode.',
        availability: r.hasModel ? '${r.modelSizeMB} MB on device' : (AeroOnDeviceService.isDownloading ? 'Downloading…' : 'Not downloaded'),
        ready: r.hasModel, active: primary == AeroEngine.tinyllama,
      ),
      AeroEngineInfo(
        id: AeroEngine.apple, name: 'Engine 2 — Apple Intelligence', subtitle: 'iPhone 15 Pro and newer • iOS 26',
        description: "Apple's on-device foundation model through a native bridge. Free and private.",
        availability: AppleIntelligenceService.statusLabel, ready: r.appleAvailable, active: primary == AeroEngine.apple,
      ),
      AeroEngineInfo(
        id: AeroEngine.ollama, name: 'Engine 3 — Ollama', subtitle: 'Surface on the same Wi-Fi',
        description: 'Bigger models on your PC. Used only when it is reachable; skipped silently otherwise.',
        availability: r.ollamaOnline ? 'Online at ${AeroSettings.ollamaUrl}' : 'Not reachable', ready: r.ollamaOnline,
        active: primary == AeroEngine.ollama,
      ),
    ];
  }
}

// --- The router: detection, auto-pick, fallback, chat history (survives tab switches) ---
class AeroRouter extends ChangeNotifier {
  AeroRouter._();
  static final AeroRouter instance = AeroRouter._();

  bool hasModel = false;
  int modelSizeMB = 0;
  bool appleAvailable = false;
  bool ollamaOnline = false;
  bool detecting = false;
  bool busy = false;
  String deviceLabel = '';
  DateTime? _lastDetect;
  final List<AeroMessage> messages = [];

  AeroEngine get primary {
    if (hasModel) return AeroEngine.tinyllama;
    if (appleAvailable) return AeroEngine.apple;
    if (ollamaOnline) return AeroEngine.ollama;
    return AeroEngine.core;
  }

  String get engineLabel {
    switch (primary) {
      case AeroEngine.core: return 'AERO Core • instant • offline';
      case AeroEngine.tinyllama: return 'Engine 1 TinyLlama • $modelSizeMB MB • offline';
      case AeroEngine.apple: return 'Engine 2 Apple Intelligence • on-device';
      case AeroEngine.ollama: return 'Engine 3 Ollama • Surface';
    }
  }

  /// Runs in the background on launch and on every resume. Never shows a dialog.
  Future<void> detect({bool force = false}) async {
    if (detecting) return;
    if (!force && _lastDetect != null && DateTime.now().difference(_lastDetect!) < const Duration(seconds: 15)) return;
    detecting = true;
    notifyListeners();
    try {
      await AeroSettings.load();
      final results = await Future.wait<Object>([
        AeroOnDeviceService.checkModelExists(),
        AeroOnDeviceService.getModelSizeMB(),
        AppleIntelligenceService.checkAvailability(),
        AiCopilotService.checkConnection(),
        _deviceLabel(),
      ]);
      hasModel = results[0] as bool;
      modelSizeMB = results[1] as int;
      appleAvailable = results[2] as bool;
      ollamaOnline = results[3] as bool;
      deviceLabel = results[4] as String;
      debugPrint('[AERO] detect: model=$hasModel ($modelSizeMB MB) apple=${AppleIntelligenceService.status} '
          'ollama=$ollamaOnline device=$deviceLabel → $engineLabel');
    } catch (e) {
      debugPrint('[AERO] detect failed: $e');
    } finally {
      _lastDetect = DateTime.now();
      detecting = false;
      notifyListeners();
    }
  }

  static Future<String> _deviceLabel() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return '${info.utsname.machine} • iOS ${info.systemVersion}';
      }
      return Platform.operatingSystem;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  List<AeroEngine> get _modelOrder => [
        if (hasModel) AeroEngine.tinyllama,
        if (appleAvailable) AeroEngine.apple,
        if (ollamaOnline) AeroEngine.ollama,
      ];

  Future<String> _run(AeroEngine e, String prompt, void Function(String)? onPartial) {
    switch (e) {
      case AeroEngine.tinyllama: return AeroOnDeviceService.generateOnDevice(prompt, onPartial: onPartial);
      case AeroEngine.apple: return AppleIntelligenceService.generateWithAppleIntelligence(prompt);
      case AeroEngine.ollama: return AiCopilotService.chat(prompt);
      case AeroEngine.core: throw AeroException(AeroErrorKind.unavailable, 'Core has no model');
    }
  }

  /// Tries each available model engine in priority order; falls back quietly. Never throws.
  Future<AeroReply> ask(String prompt, {void Function(String partial)? onPartial, bool allowCore = true}) async {
    if (allowCore) {
      final core = await AeroOnDeviceService.coreFastPath(prompt, engineLine: engineLabel);
      if (core != null) return AeroReply(core, AeroEngine.core);
    }
    final failures = <String>[];
    for (final e in _modelOrder) {
      try {
        final text = await _run(e, prompt, onPartial);
        return AeroReply(text, e, note: failures.isEmpty ? null : 'Fell back: ${failures.join('; ')}');
      } on AeroException catch (ex) {
        debugPrint('[AERO] ${e.shortName} failed → $ex');
        failures.add('${e.shortName} ${ex.kind.name}');
        if (ex.kind == AeroErrorKind.modelMissing || ex.kind == AeroErrorKind.modelIncomplete) {
          hasModel = false;
          notifyListeners();
        }
        if (e == AeroEngine.ollama) {
          ollamaOnline = false;
          notifyListeners();
        }
      } catch (ex) {
        debugPrint('[AERO] ${e.shortName} crashed → $ex');
        failures.add('${e.shortName} error');
      }
    }
    final hint = AeroOnDeviceService.isDownloading
        ? 'The offline model is downloading — once it finishes I can answer this fully.'
        : 'That one needs a language model. Tap Download in the bar above once (~640 MB) and I\'ll answer anything offline, VPN on or off.';
    return AeroReply(
      'AERO Core: $hint\nInstant right now: "summarize my week", "habits left today", "my tasks", "what time is it".',
      AeroEngine.core,
      note: failures.isEmpty ? null : 'Tried: ${failures.join('; ')}',
    );
  }

  /// Chat entry point: keeps history, streams into the last bubble.
  Future<void> send(String text) async {
    if (busy || text.trim().isEmpty) return;
    busy = true;
    messages.add(AeroMessage(isUser: true, text: text.trim()));
    final bubble = AeroMessage(isUser: false, text: '', streaming: true);
    messages.add(bubble);
    notifyListeners();
    try {
      final reply = await ask(text.trim(), onPartial: (partial) {
        bubble.text = partial;
        notifyListeners();
      });
      bubble.text = reply.text;
      bubble.engine = reply.engine;
      bubble.note = reply.note;
    } catch (e) {
      bubble.text = 'AERO error: $e';
      bubble.engine = AeroEngine.core;
    } finally {
      bubble.streaming = false;
      busy = false;
      notifyListeners();
    }
  }

  /// Writing Hub helper — always goes to a model engine (no Core shortcuts). Long drafts are trimmed for TinyLlama's 2K context.
  Future<AeroReply> assistWriting(String instruction, String text) {
    final body = text.length > 4500 ? '${text.substring(0, 4500)}\n[…trimmed]' : text;
    return ask('$instruction\n\n---\n$body', allowCore: false);
  }

  void clear() {
    messages.clear();
    notifyListeners();
  }
}


// --- P2P Sync Service (Local Wi-Fi, zero cloud) ---
class P2PSyncService {
  static HttpServer? _server;
  static bool _isServing = false;
  static String? _localIp;
  static Future<String> getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (addr.address.startsWith('192.') || addr.address.startsWith('10.') || addr.address.startsWith('172.')) {
              _localIp = addr.address;
              return addr.address;
            }
          }
        }
      }
    } catch(_){}
    return '127.0.0.1';
  }
  static Future<bool> startServer() async {
    try {
      final dbPath = await getDatabasesPath();
      final filePath = path.join(dbPath, 'onyx_beacon.db');
      final ip = await getLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      _isServing = true;
      _server!.listen((HttpRequest req) async {
        if(req.uri.path == '/db'){
          final file = File(filePath);
          if(await file.exists()){
            req.response.headers.set('Content-Type', 'application/octet-stream');
            req.response.headers.set('Content-Disposition', 'attachment; filename=onyx_beacon.db');
            await req.response.addStream(file.openRead());
            await req.response.close();
          } else {
            req.response.statusCode = 404;
            req.response.write('DB not found');
            await req.response.close();
          }
        } else if(req.uri.path == '/status'){
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'status':'Onyx Beacon Sync Server','ip':ip,'port':8765,'db_size': await File(filePath).length()}));
          await req.response.close();
        } else {
          req.response.write('Onyx Beacon P2P Sync — GET /db to download, /status for info');
          await req.response.close();
        }
      });
      return true;
    } catch(e){ debugPrint('P2P server error: $e'); return false; }
  }
  static Future<void> stopServer() async {
    try { await _server?.close(); _isServing=false; } catch(_){}
  }
  static bool get isServing => _isServing;
  static String? get serverIp => _localIp;
  static Future<bool> syncFromServer(String serverIp) async {
    try {
      final url = 'http://$serverIp:8765/db';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if(res.statusCode==200){
        final dbPath = await getDatabasesPath();
        final filePath = path.join(dbPath, 'onyx_beacon.db');
        final backupPath = path.join(dbPath, 'onyx_beacon_backup_${DateTime.now().millisecondsSinceEpoch}.db');
        final current = File(filePath);
        if(await current.exists()) await current.copy(backupPath);
        await File(filePath).writeAsBytes(res.bodyBytes);
        return true;
      }
      return false;
    } catch(e){ debugPrint('P2P client error: $e'); return false; }
  }
}

// --- Weekly Review PDF Service ---
class WeeklyReviewService {
  static Future<String> generateWeeklyPdf() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final weekAgoStr = DateFormat('yyyy-MM-dd').format(weekAgo);
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      
      final habits = await db.query('habits');
      final completions = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [weekAgoStr]);
      final tasks = await db.query('tasks');
      final tasksCompleted = await db.rawQuery('SELECT COUNT(*) as c FROM tasks WHERE isCompleted=1');
      final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [weekAgoStr]);
      final journals = await db.query('journal_entries', where: 'date >= ?', whereArgs: [weekAgoStr]);
      
      double income=0, expense=0;
      for(var t in txs){ final amt=(t['amount'] as num).toDouble(); if(t['type']=='Income') income+=amt; else expense+=amt; }
      int totalWords=0;
      for(var j in journals){ totalWords+= (j['content'] as String).split(RegExp(r'\s+')).length; }
      
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: pdfLib.PdfPageFormat.a4,
          build: (ctx) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Onyx Beacon — Weekly Life Review',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              'Period: $weekAgoStr to $todayStr — '
              'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
              style: pw.TextStyle(
                fontSize: 10,
                color: pdfLib.PdfColors.grey,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Executive Summary',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Bullet(
              text: 'Habits Tracked: ${habits.length} — '
              'Completions This Week: ${completions.length}',
            ),
            pw.Bullet(
              text: 'Tasks: ${tasks.length} total, '
              '${tasksCompleted.first['c']} completed',
            ),
            pw.Bullet(
              text: 'Finance: Income \$${income.toStringAsFixed(2)} — '
              'Expense \$${expense.toStringAsFixed(2)} — '
              'Net \$${(income-expense).toStringAsFixed(2)}',
            ),
            pw.Bullet(
              text: 'Writing: ${journals.length} entries — '
              '$totalWords words',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Habit Completions',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Table.fromTextArray(
              headers: ['Habit','Completions This Week'],
              data: habits.map((h){
                final count = completions.where(
                  (c)=>c['habit_id']==h['id']
                ).length;
                return [h['name'], count.toString()];
              }).toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Finance Ledger — Past 7 Days',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Table.fromTextArray(
              headers: ['Date','Title','Type','Amount','Category'],
              data: txs.map((t)=>[
                t['date'],
                t['title'],
                t['type'],
                '\$${t['amount']}',
                t['category']
              ]).toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Writing Output',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Table.fromTextArray(
              headers: ['Date','Title','Category','Words'],
              data: journals.map((j){
                final wc = (j['content'] as String).split(
                  RegExp(r'\s+')
                ).length;
                return [
                  j['date'],
                  j['title'],
                  j['category'],
                  wc.toString()
                ];
              }).toList(),
            ),
          ],
        ),
      );
      
      final dir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory(path.join(dir.path, 'OnyxBeacon','reports'));
      if(!await reportsDir.exists()) await reportsDir.create(recursive: true);
      final fileName = 'Weekly_Review_${DateFormat('yyyy-MM-dd').format(now)}.pdf';
      final file = File(path.join(reportsDir.path, fileName));
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch(e){ debugPrint('PDF error: $e'); return ''; }
  }
  static Future<void> shareWeeklyPdf() async {
    final pdfPath = await generateWeeklyPdf();
    if(pdfPath.isNotEmpty){
      await Share.shareXFiles([XFile(pdfPath)], text: 'Onyx Beacon Weekly Review');
    }
  }
}

// ==================== COLOR CODES + DAILY BRIEFING WIDGET ====================

class ColorCodes {
  static const List<String> palette = [
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#96CEB4',
    '#FFEAA7',
    '#DDA0DD',
    '#98D8C8',
    '#F7DC6F',
    '#BB8FCE',
    '#85C1E2',
    '#F8B500',
    '#6C5CE7',
    '#A29BFE',
    '#FD79A8',
    '#FDCB6E',
  ];
  static Color fromHex(String hex) {
    try {
      final b = StringBuffer();
      if (hex.length == 6 || hex.length == 7) b.write('ff');
      b.write(hex.replaceFirst('#',''));
      return Color(int.parse(b.toString(), radix: 16));
    } catch (_) { return const Color(0xFF4A4E69); }
  }
}

class DailyBriefingWidget extends StatefulWidget {
  final Function(int)? onNavigateToTab;
  const DailyBriefingWidget({super.key, this.onNavigateToTab});
  @override
  State<DailyBriefingWidget> createState() => _DailyBriefingWidgetState();
}
class _DailyBriefingWidgetState extends State<DailyBriefingWidget> {
  int habitsDue = 0, tasksPending = 0; double netToday = 0;
  List<Map<String, dynamic>> dueHabits = [];
  List<Map<String, dynamic>> pendingTasks = [];
  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final habits = await db.query('habits');
      final completions = await db.query('habit_completions', where: 'completed_date = ?', whereArgs: [today]);
      final completedIds = completions.map((e) => e['habit_id']).toSet();
      final due = habits.where((h) => !completedIds.contains(h['id'])).toList();
      final tasks = await db.query('tasks', where: 'isCompleted = 0');
      final txs = await db.query('transactions', where: 'date = ?', whereArgs: [today]);
      double net = 0;
      for(var t in txs){ final amt = (t['amount'] as num).toDouble(); net += t['type'] == 'Income' ? amt : -amt; }
      setState((){
        habitsDue = due.length;
        tasksPending = tasks.length;
        netToday = net;
        dueHabits = due;
        pendingTasks = tasks;
      });
    } catch(_){}
  }
  void _showDueHabitsDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Habits Due Today ($habitsDue)'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: dueHabits.isEmpty
          ? const Center(child: Text('All habits done! 🎉'))
          : ListView.builder(
              itemCount: dueHabits.length,
              itemBuilder: (c,i){
                final habit = dueHabits[i];
                return ListTile(
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ColorCodes.fromHex(habit['color'] ?? '#FF6B6B'),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(habit['name']),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: () async {
                      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                      await DatabaseHelper.instance.toggleHabitCompletion(habit['id'] as int, today);
                      Navigator.pop(ctx);
                      _load();
                      if(mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${habit['name']} done! 🔥')),
                        );
                      }
                    },
                  ),
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: ()=>Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ));
  }
  void _showPendingTasksDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Tasks Pending ($tasksPending)'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: pendingTasks.isEmpty
          ? const Center(child: Text('No pending tasks!'))
          : ListView.builder(
              itemCount: pendingTasks.length,
              itemBuilder: (c,i){
                final task = pendingTasks[i];
                return ListTile(
                  leading: const Icon(Icons.task_alt_outlined),
                  title: Text(task['title']),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_box_outline_blank),
                    onPressed: () async {
                      await DatabaseHelper.instance.updateTaskCompletion(task['id'] as int, 1);
                      Navigator.pop(ctx);
                      _load();
                      if(mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${task['title']} completed!')),
                        );
                      }
                    },
                  ),
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: ()=>Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        if(pendingTasks.isNotEmpty)
          TextButton(
            onPressed: (){
              Navigator.pop(ctx);
              widget.onNavigateToTab?.call(2);
            },
            child: const Text('Go to Tasks'),
          ),
      ],
    ));
  }
  @override
  Widget build(BuildContext context){
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Row(
              children:[
                const Icon(Icons.wb_sunny_outlined, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Daily Briefing — Today (Tap to act)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _load,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children:[
                Expanded(
                  child: InkWell(
                    onTap: habitsDue > 0 ? _showDueHabitsDialog : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children:[
                        Icon(Icons.bolt, color: Colors.orange, size: 18),
                        Text(
                          '$habitsDue',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Habits Due',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        if(habitsDue > 0)
                          const Text(
                            'Tap to complete',
                            style: TextStyle(fontSize: 8, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: tasksPending > 0 ? _showPendingTasksDialog : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children:[
                        Icon(Icons.task_alt, color: Colors.blue, size: 18),
                        Text(
                          '$tasksPending',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Tasks',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        if(tasksPending > 0)
                          const Text(
                            'Tap to view',
                            style: TextStyle(fontSize: 8, color: Colors.blue),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onNavigateToTab?.call(3),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children:[
                        Icon(Icons.account_balance_wallet, color: Colors.green, size: 18),
                        Text(
                          '\$${netToday.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: netToday>=0?Colors.green:Colors.red,
                          ),
                        ),
                        const Text(
                          'Net Today',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const Text(
                          'Tap for Finance',
                          style: TextStyle(fontSize: 8, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== APP SHELL & NAVIGATION ====================

class MainDashboardShell extends StatefulWidget {
  const MainDashboardShell({super.key});

  @override
  State<MainDashboardShell> createState() => _MainDashboardShellState();
}


class _MainDashboardShellState extends State<MainDashboardShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  void setTab(int idx){ setState(()=>_currentIndex = idx); }
  @override
  void initState(){ super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose(){ WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    // Coming back from Settings (Apple Intelligence toggle), VPN change, or Wi-Fi change → re-pick engine.
    if(state == AppLifecycleState.resumed){ AeroRouter.instance.detect(); }
  }
  List<Widget> get _pages => [
    DashboardHomeTab(onNavigateToTab: setTab),
    const HabitsTab(),
    const TasksTab(),
    const FinanceTab(),
    const JournalTab(),
    const AiChatTab(),
    const GalleryTab(),
    const GameTab(),
  ];
  Widget _buildFixedTab(BuildContext context, int index, IconData icon, String label, bool selected){
    return InkWell(onTap: ()=>setState(()=>_currentIndex=index), child: Container(padding: const EdgeInsets.symmetric(horizontal:18, vertical:8), decoration: BoxDecoration(color: selected ? Colors.black : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Column(mainAxisSize: MainAxisSize.min, children:[Icon(icon, size:22, color: selected ? Colors.white : Colors.grey.shade700), const SizedBox(height:2), Text(label, style: TextStyle(fontSize:10, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey.shade700))])) );
  }
  Widget _buildSlidableTab(BuildContext context, int index, IconData icon, String label, bool selected, {bool accent=false}){
    return InkWell(onTap: ()=>setState(()=>_currentIndex=index), child: Container(padding: const EdgeInsets.symmetric(horizontal:14, vertical:8), margin: const EdgeInsets.only(right:4), decoration: BoxDecoration(color: selected ? (accent ? Colors.deepPurple : Colors.grey.shade900) : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), child: Column(mainAxisSize: MainAxisSize.min, children:[Icon(icon, size:20, color: selected ? Colors.white : Colors.black54), const SizedBox(height:2), Text(label, style: TextStyle(fontSize:10, color: selected ? Colors.white : Colors.black87))])) );
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        height: 78,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children:[
          _buildFixedTab(context, 0, Icons.dashboard, "Command", _currentIndex==0),
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), child: Row(children:[
            _buildSlidableTab(context, 1, Icons.bolt, "Habits", _currentIndex==1),
            _buildSlidableTab(context, 2, Icons.check_circle, "Tasks", _currentIndex==2),
            _buildSlidableTab(context, 3, Icons.account_balance_wallet, "Finances", _currentIndex==3),
            _buildSlidableTab(context, 4, Icons.book, "Writing", _currentIndex==4),
            _buildSlidableTab(context, 5, Icons.smart_toy, "AERO", _currentIndex==5),
            _buildSlidableTab(context, 6, Icons.photo_library, "Gallery", _currentIndex==6),
            _buildSlidableTab(context, 7, Icons.videogame_asset, "Gaming", _currentIndex==7, accent:true),
          ]))),
        ]),
      ),
    );
  }
}


// ==================== 1. COMMAND DASHBOARD TAB (PUSH 4 Sovereign) ====================
class DashboardHomeTab extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const DashboardHomeTab({super.key, this.onNavigateToTab});

  @override
  State<DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends State<DashboardHomeTab> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, List<Map<String, dynamic>>>? _searchResults;
  bool _isSearching = false;
  int _habitCount = 0;
  int _taskCount = 0;
  int _txCount = 0;
  int _journalCount = 0;
  double _weeklyNet = 0;
  int _weeklyWords = 0;
  List<Map<String, dynamic>> _recentCompletions = [];

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _loadAnalytics();
  }

  Future<void> _loadCounts() async {
    final db = await DatabaseHelper.instance.database;
    final habits = await db.rawQuery('SELECT COUNT(*) as c FROM habits');
    final tasks = await db.rawQuery('SELECT COUNT(*) as c FROM tasks');
    final txs = await db.rawQuery('SELECT COUNT(*) as c FROM transactions');
    final journals = await db.rawQuery('SELECT COUNT(*) as c FROM journal_entries');
    setState(() {
      _habitCount = habits.first['c'] as int;
      _taskCount = tasks.first['c'] as int;
      _txCount = txs.first['c'] as int;
      _journalCount = journals.first['c'] as int;
    });
  }

  Future<void> _loadAnalytics() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final weekAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)));
      final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [weekAgo]);
      double net = 0;
      for(var t in txs){ final amt = (t['amount'] as num).toDouble(); net += t['type']=='Income'?amt:-amt; }
      final journals = await db.query('journal_entries', where: 'date >= ?', whereArgs: [weekAgo]);
      int words = 0;
      for(var j in journals){ words += (j['content'] as String).split(RegExp(r'\s+')).length; }
      final completions = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [weekAgo], orderBy: 'completed_date DESC', limit: 10);
      setState((){ _weeklyNet = net; _weeklyWords = words; _recentCompletions = completions; });
    } catch(_){}
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = null; });
      return;
    }
    setState(() => _isSearching = true);
    final results = await DatabaseHelper.instance.globalSearch(query);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Onyx Beacon — Command Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        titleSpacing: 16,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'Weekly PDF Review', onPressed: () => WeeklyReviewService.shareWeeklyPdf()),
          IconButton(icon: const Icon(Icons.backup_outlined), tooltip: 'Full Backup JSON', onPressed: () => ExportService.exportFullBackup()),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints){
          final isWide = constraints.maxWidth > 600;
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text('Welcome back, Caleb.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DailyBriefingWidget(onNavigateToTab: widget.onNavigateToTab),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Global search: habits, tasks, finance, writing...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: (){ _searchController.clear(); _doSearch(''); }) : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: _doSearch,
                onSubmitted: _doSearch,
              ),
              const SizedBox(height: 16),
              if (_searchResults != null) ...[
                if (_isSearching) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('Search Results for "${_searchController.text}"', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._buildSearchResults(),
                const Divider(height: 32),
              ],
              GridView.count(
                crossAxisCount: isWide ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  MetricCard(title: 'Habits', value: '$_habitCount Tracked', icon: Icons.bolt, color: Colors.orange),
                  MetricCard(title: 'Tasks', value: '$_taskCount Active', icon: Icons.task_alt, color: Colors.blue),
                  MetricCard(title: 'Finance Ledger', value: '$_txCount Transactions', icon: Icons.account_balance_wallet, color: Colors.green),
                  MetricCard(title: 'Writing Studio', value: '$_journalCount Drafts', icon: Icons.menu_book, color: Colors.purple),
                  MetricCard(title: 'Weekly Net', value: '\$${_weeklyNet.toStringAsFixed(0)}', icon: Icons.trending_up, color: _weeklyNet>=0?Colors.green:Colors.red),
                  MetricCard(title: 'Words This Week', value: '$_weeklyWords words', icon: Icons.edit_note, color: Colors.indigo),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Cross-Module Analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              CrossModuleAnalyticsWidget(weeklyNet: _weeklyNet, weeklyWords: _weeklyWords, habitCount: _habitCount),
              const SizedBox(height: 16),
              const Text('Habit Heatmap — Last 42 Days', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const HabitHeatmapWidget(),
              const SizedBox(height: 16),
              const WeeklyReviewCard(),
              const SizedBox(height: 12),
              const P2PSyncCard(),
              const SizedBox(height: 12),
              AeroStatusCard(onOpen: () => widget.onNavigateToTab?.call(5)),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Quick Export'),
                  subtitle: const Text('Backup entire vault as JSON / Encrypted .enc'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children:[
                    IconButton(icon: const Icon(Icons.lock_outline), tooltip: 'Encrypted .enc', onPressed: ()=>_showEncryptedDialog(context)),
                    ElevatedButton(onPressed: () => ExportService.exportFullBackup(), child: const Text('Export')),
                  ]),
                ),
              ),
            ],
          );
        }
      ),
    );
  }


  void _showEncryptedDialog(BuildContext context){
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('Encrypted Backup'),
      content: Column(mainAxisSize: MainAxisSize.min, children:[const Text('Enter password (min 4 chars) — remember it!'), const SizedBox(height:12), TextField(controller:c, obscureText:true, decoration: const InputDecoration(labelText:'Password', border: OutlineInputBorder()))]),
      actions:[TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: (){ if(c.text.trim().length>=4){ Navigator.pop(ctx); ExportService.exportEncryptedBackup(c.text.trim()); }}, child: const Text('Encrypt & Export'))],
    ));
  }
  List<Widget> _buildSearchResults() {
    if (_searchResults == null) return [];
    final List<Widget> widgets = [];
    _searchResults!.forEach((key, list) {
      if (list.isNotEmpty) {
        widgets.add(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('$key: ${list.length} found', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600))));
        for (var item in list.take(3)) {
          String title = item['name'] ?? item['title'] ?? 'Untitled';
          widgets.add(ListTile(dense: true, title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(key), leading: const Icon(Icons.search, size: 16)));
        }
      }
    });
    if (widgets.isEmpty) widgets.add(const ListTile(title: Text('No results found')));
    return widgets;
  }
}



class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ==================== 2. HABITS TAB (with Streaks + Heatmap) ====================
class HabitsTab extends StatefulWidget {
  const HabitsTab({super.key});

  @override
  State<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends State<HabitsTab> {
  List<Map<String, dynamic>> _habits = [];
  Map<int, int> _streaks = {};
  Map<int, List<String>> _completionsMap = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshHabits();
  }

  Future<void> _refreshHabits() async {
    final habits = await DatabaseHelper.instance.getHabits();
    Map<int, int> streaks = {};
    Map<int, List<String>> compMap = {};
    for (var h in habits) {
      int id = h['id'] as int;
      final comps = await DatabaseHelper.instance.getHabitCompletions(id);
      compMap[id] = comps.map((e) => e['completed_date'] as String).toList();
      streaks[id] = await DatabaseHelper.instance.getHabitStreak(id);
    }
    setState(() {
      _habits = habits;
      _streaks = streaks;
      _completionsMap = compMap;
    });
  }

  void _showHabitDialog({int? id, String? initialName, String? initialColor}) {
    final controller = TextEditingController(text: initialName ?? '');
    final isEditing = id != null;
    String selectedColor = initialColor ?? ColorCodes.palette[_habits.length % ColorCodes.palette.length];
    showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(isEditing ? 'Edit Habit' : 'New Habit'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter habit name'),
            autofocus: !isEditing,
          ),
          const SizedBox(height: 14),
          const Text('Color', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: ColorCodes.palette.map((hex) {
            final selected = hex == selectedColor;
            return GestureDetector(
              onTap: () => setDialogState(() => selectedColor = hex),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: ColorCodes.fromHex(hex),
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.black : Colors.transparent, width: 2.5),
                ),
                child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
            );
          }).toList()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final habitName = controller.text.trim();
              if (habitName.isNotEmpty) {
                if (id != null) {
                  await DatabaseHelper.instance.updateHabit(id, habitName, color: selectedColor);
                } else {
                  await DatabaseHelper.instance.insertHabit(habitName, color: selectedColor);
                }
                await _refreshHabits();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      )),
    );
  }

  Future<void> _toggleToday(int habitId) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await DatabaseHelper.instance.toggleHabitCompletion(habitId, today);
    await _refreshHabits();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _habits.where((h) => (h['name'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Onyx Beacon Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Habits JSON',
            onPressed: () async {
              final data = {
                'habits': _habits,
                'completions': _completionsMap,
              };
              await ExportService.exportJson('habits_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json', data);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search habits...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No habits recorded yet. Tap + to add one.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final habit = filtered[index];
                      final id = habit['id'] as int;
                      final streak = _streaks[id] ?? 0;
                      final completions = _completionsMap[id] ?? [];
                      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final doneToday = completions.contains(todayStr);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: ColorCodes.fromHex(habit['color'] ?? '#FF6B6B'),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          habit['name'],
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )),
                                  Chip(
                                    label: Text('🔥 $streak streak', style: const TextStyle(fontSize: 12)),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: streak > 0 ? Colors.orange.shade100 : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Heatmap last 14 days
                              SizedBox(
                                height: 30,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: 14,
                                  itemBuilder: (context, i) {
                                    final date = DateTime.now().subtract(Duration(days: 13 - i));
                                    final dateStr = DateFormat('yyyy-MM-dd').format(date);
                                    final isDone = completions.contains(dateStr);
                                    return Container(
                                      width: 22,
                                      height: 22,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: isDone ? Colors.green : Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(4),
                                        border: dateStr == todayStr ? Border.all(color: Colors.blue, width: 2) : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          DateFormat('d').format(date),
                                          style: TextStyle(fontSize: 8, color: isDone ? Colors.white : Colors.black54),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                        onPressed: () => _showHabitDialog(id: habit['id'], initialName: habit['name'], initialColor: habit['color'] as String?),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        onPressed: () async {
                                          await DatabaseHelper.instance.deleteHabit(habit['id']);
                                          await _refreshHabits();
                                        },
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    icon: Icon(doneToday ? Icons.check_circle : Icons.circle_outlined, size: 18),
                                    label: Text(doneToday ? 'Done Today' : 'Mark Today'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: doneToday ? Colors.green : null,
                                      foregroundColor: doneToday ? Colors.white : null,
                                    ),
                                    onPressed: () => _toggleToday(id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showHabitDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==================== 3. TASKS TAB (with Search) ====================
class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  List<Map<String, dynamic>> _tasks = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshTasks();
  }

  Future<void> _refreshTasks() async {
    try {
      final tasks = await DatabaseHelper.instance.getTasks();
      setState(() {
        _tasks = tasks;
      });
    } catch (e) {
      setState(() {
        _tasks = [];
      });
    }
  }

  void _showTaskDialog({int? id, String? initialTitle}) {
    final controller = TextEditingController(text: initialTitle ?? '');
    final isEditing = id != null;
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(isEditing ? 'Edit Task' : 'New Task'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter task description'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final taskTitle = controller.text.trim();
              if (taskTitle.isNotEmpty) {
                if (isEditing) {
                  await DatabaseHelper.instance.updateTaskTitle(id, taskTitle);
                } else {
                  await DatabaseHelper.instance.insertTask(taskTitle);
                }
                await _refreshTasks();
                if (mounted) Navigator.pop(context);
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _tasks.where((t) => (t['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & To-dos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Tasks',
            onPressed: () async {
              await ExportService.exportJson('tasks_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json', _tasks);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No tasks found.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final task = filtered[index];
                      final isDone = task['isCompleted'] == 1;
                      return CheckboxListTile(
                        title: Text(
                          task['title'],
                          style: TextStyle(
                            decoration: isDone ? TextDecoration.lineThrough : null,
                            color: isDone ? Colors.grey : null,
                          ),
                        ),
                        value: isDone,
                        onChanged: (bool? value) async {
                          await DatabaseHelper.instance.updateTaskCompletion(task['id'], value == true ? 1 : 0);
                          await _refreshTasks();
                        },
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                              onPressed: () => _showTaskDialog(id: task['id'], initialTitle: task['title']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () async {
                                await DatabaseHelper.instance.deleteTask(task['id']);
                                await _refreshTasks();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==================== 4. FINANCE TAB (Charts + Search + Filter + Export) ====================
class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _incomeCategories = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showCharts = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshFinanceData();
  }

  Future<void> _refreshFinanceData() async {
    try {
      final txs = await DatabaseHelper.instance.getTransactions();
      final expCats = await DatabaseHelper.instance.getFinanceCategories('Expense');
      final incCats = await DatabaseHelper.instance.getFinanceCategories('Income');
      setState(() {
        _transactions = txs;
        _expenseCategories = expCats;
        _incomeCategories = incCats;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _transactions = [];
        _expenseCategories = [];
        _incomeCategories = [];
        _filteredTransactions = [];
      });
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_transactions);
    if (_searchQuery.isNotEmpty) {
      result = result.where((t) => (t['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase()) || (t['category'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    if (_startDate != null) {
      result = result.where((t) {
        try {
          final d = DateTime.parse(t['date'] as String);
          return !d.isBefore(_startDate!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (_endDate != null) {
      result = result.where((t) {
        try {
          final d = DateTime.parse(t['date'] as String);
          return !d.isAfter(_endDate!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    setState(() {
      _filteredTransactions = result;
    });
  }

  double get _totalIncome {
    return _filteredTransactions.where((t) => t['type'] == 'Income').fold(0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
  }
  double get _totalExpense {
    return _filteredTransactions.where((t) => t['type'] == 'Expense').fold(0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
  }
  double get _netBalance => _totalIncome - _totalExpense;

  Map<String, double> get _expenseByCategory {
    final map = <String, double>{};
    for (var tx in _filteredTransactions.where((t) => t['type'] == 'Expense')) {
      final cat = tx['category'] as String;
      map[cat] = (map[cat] ?? 0) + (tx['amount'] as num).toDouble();
    }
    return map;
  }

  Map<String, double> get _monthlyTotals {
    final map = <String, double>{};
    for (var tx in _filteredTransactions) {
      try {
        final d = DateTime.parse(tx['date'] as String);
        final key = DateFormat('yyyy-MM').format(d);
        final amount = (tx['amount'] as num).toDouble() * (tx['type'] == 'Income' ? 1 : -1);
        map[key] = (map[key] ?? 0) + amount;
      } catch (_) {}
    }
    // Sort by key
    final sortedKeys = map.keys.toList()..sort();
    return {for (var k in sortedKeys) k: map[k]!};
  }

  void _manageCategoriesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Categories'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')]),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildCategoryList('Expense', _expenseCategories, setDialogState),
                            _buildCategoryList('Income', _incomeCategories, setDialogState),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryList(String type, List<Map<String, dynamic>> categories, StateSetter setDialogState) {
    final controller = TextEditingController();
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TextField(controller: controller, decoration: InputDecoration(hintText: 'New $type category'))),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.green),
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  await DatabaseHelper.instance.insertFinanceCategory(controller.text.trim(), type);
                  controller.clear();
                  await _refreshFinanceData();
                  setDialogState(() {});
                }
              },
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return ListTile(
                title: Text(cat['name']),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                      onPressed: () async {
                        final editController = TextEditingController(text: cat['name']);
                        await showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Edit Category'),
                            content: TextField(controller: editController, autofocus: true),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () async {
                                  if (editController.text.trim().isNotEmpty) {
                                    await DatabaseHelper.instance.updateFinanceCategory(cat['id'], editController.text.trim());
                                    await _refreshFinanceData();
                                    setDialogState(() {});
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  }
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () async {
                        await DatabaseHelper.instance.deleteFinanceCategory(cat['id']);
                        await _refreshFinanceData();
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTransactionDialog({Map<String, dynamic>? transaction}) async {
    final isEditing = transaction != null;
    final titleController = TextEditingController(text: isEditing ? transaction['title'] : '');
    final amountController = TextEditingController(text: isEditing ? transaction['amount'].toString() : '');
    String selectedType = isEditing ? transaction['type'] : 'Expense';
    List<Map<String, dynamic>> availableCats = selectedType == 'Income' ? _incomeCategories : _expenseCategories;
    String selectedCategory = isEditing ? transaction['category'] : (availableCats.isNotEmpty ? availableCats.first['name'] : 'General');
    String selectedDate = isEditing ? transaction['date'] : DateTime.now().toIso8601String().substring(0, 10);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<Map<String, dynamic>> currentCats = selectedType == 'Income' ? _incomeCategories : _expenseCategories;
            bool categoryExists = currentCats.any((c) => c['name'] == selectedCategory);
            if (!categoryExists && currentCats.isNotEmpty) {
              selectedCategory = currentCats.first['name'];
            }
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEditing ? 'Edit Transaction' : 'New Transaction'),
                  IconButton(
                    icon: const Icon(Icons.category, size: 20),
                    tooltip: 'Manage Categories',
                    onPressed: () {
                      Navigator.pop(context);
                      _manageCategoriesDialog();
                    },
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Expense', label: Text('Expense'), icon: Icon(Icons.arrow_downward, color: Colors.red)),
                        ButtonSegment(value: 'Income', label: Text('Income'), icon: Icon(Icons.arrow_upward, color: Colors.green)),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setDialogState(() {
                          selectedType = newSelection.first;
                          List<Map<String, dynamic>> newCats = selectedType == 'Income' ? _incomeCategories : _expenseCategories;
                          selectedCategory = newCats.isNotEmpty ? newCats.first['name'] : 'General';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title / Merchant', hintText: 'e.g., Grocery Store, Client Payment')),
                    const SizedBox(height: 12),
                    TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (\$)', hintText: '0.00')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currentCats.any((c) => c['name'] == selectedCategory) ? selectedCategory : (currentCats.isNotEmpty ? currentCats.first['name'] : null),
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: currentCats.map((cat) {
                        return DropdownMenuItem<String>(value: cat['name'].toString(), child: Text(cat['name'].toString()));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCategory = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: selectedDate),
                      decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                      onChanged: (val) {
                        selectedDate = val;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                    if (title.isNotEmpty && amount > 0) {
                      final row = {'title': title, 'amount': amount, 'type': selectedType, 'category': selectedCategory, 'date': selectedDate};
                      if (isEditing) {
                        await DatabaseHelper.instance.updateTransaction(transaction['id'], row);
                      } else {
                        await DatabaseHelper.instance.insertTransaction(row);
                      }
                      await _refreshFinanceData();
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  child: Text(isEditing ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Ledger & Budget'),
        actions: [
          IconButton(icon: Icon(_showCharts ? Icons.bar_chart : Icons.bar_chart_outlined), tooltip: 'Toggle Charts', onPressed: () => setState(() => _showCharts = !_showCharts)),
          IconButton(icon: const Icon(Icons.date_range), tooltip: 'Filter by Date', onPressed: _pickDateRange),
          IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Manage Categories', onPressed: _manageCategoriesDialog),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'csv') ExportService.exportTransactionsCsv(_filteredTransactions);
              if (v == 'json') ExportService.exportJson('transactions_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json', _filteredTransactions);
              if (v == 'clear_filter') {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                  _searchQuery = '';
                  _searchController.clear();
                });
                _applyFilters();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              const PopupMenuItem(value: 'json', child: Text('Export JSON')),
              const PopupMenuItem(value: 'clear_filter', child: Text('Clear Filters')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions by title or category...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
            ),
          ),
          if (_startDate != null || _endDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Chip(
                label: Text('Filter: ${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : '...'} to ${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : '...'}'),
                deleteIcon: const Icon(Icons.clear, size: 18),
                onDeleted: () {
                  setState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                  _applyFilters();
                },
              ),
            ),
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Net Balance', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('\$${_netBalance.toStringAsFixed(2)}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _netBalance >= 0 ? Colors.green : Colors.red)),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [const Text('Income', style: TextStyle(color: Colors.grey, fontSize: 13)), const SizedBox(height: 4), Text('+\$${_totalIncome.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16))]),
                      Container(height: 30, width: 1, color: Colors.grey.shade300),
                      Column(children: [const Text('Expenses', style: TextStyle(color: Colors.grey, fontSize: 13)), const SizedBox(height: 4), Text('-\$${_totalExpense.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_showCharts && _filteredTransactions.isNotEmpty) ...[
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(child: _buildExpensePieChart()),
                  Expanded(child: _buildMonthlyBarChart()),
                ],
              ),
            ),
            const Divider(),
          ],
          Expanded(
            child: _filteredTransactions.isEmpty
                ? const Center(child: Text('No transactions found.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _filteredTransactions.length,
                    itemBuilder: (context, index) {
                      final tx = _filteredTransactions[index];
                      final isIncome = tx['type'] == 'Income';
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: isIncome ? Colors.green.shade100 : Colors.red.shade100, child: Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward, color: isIncome ? Colors.green : Colors.red)),
                        title: Text(tx['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${tx['category']} • ${tx['date']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("${isIncome ? '+' : '-'}\$${(tx['amount'] as num).toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isIncome ? Colors.green : Colors.red)),
                            IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () => _showTransactionDialog(transaction: tx)),
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () async { await DatabaseHelper.instance.deleteTransaction(tx['id']); await _refreshFinanceData(); }),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showTransactionDialog(), child: const Icon(Icons.add)),
    );
  }

  Widget _buildExpensePieChart() {
    final data = _expenseByCategory;
    if (data.isEmpty) return const Center(child: Text('No expense data'));
    final colors = [Colors.red, Colors.orange, Colors.blue, Colors.green, Colors.purple, Colors.teal, Colors.amber, Colors.indigo];
    int i = 0;
    final sections = data.entries.map((e) {
      final color = colors[i % colors.length];
      i++;
      return PieChartSectionData(value: e.value, title: '${e.key}\n\$${e.value.toStringAsFixed(0)}', color: color, radius: 60, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold));
    }).toList();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            const Text('Expenses by Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 20))),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyBarChart() {
    final monthly = _monthlyTotals;
    if (monthly.isEmpty) return const Center(child: Text('No monthly data'));
    final spots = <FlSpot>[];
    final labels = monthly.keys.toList();
    for (int idx = 0; idx < labels.length; idx++) {
      spots.add(FlSpot(idx.toDouble(), monthly[labels[idx]]!));
    }
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            const Text('Monthly Net', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(
              child: BarChart(
                BarChartData(
                  barGroups: spots.map((s) => BarChartGroupData(x: s.x.toInt(), barRods: [BarChartRodData(toY: s.y, color: s.y >= 0 ? Colors.green : Colors.red, width: 12)])).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) { if (val.toInt() < labels.length) { return Text(labels[val.toInt()].substring(5), style: const TextStyle(fontSize: 9)); } return const Text(''); })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 5. JOURNAL & WRITING STUDIO TAB (with Search + Export) ====================

// ==================== PUSH 4 WIDGETS — Analytics, Heatmap, Weekly Review, P2P, AI ====================
class CrossModuleAnalyticsWidget extends StatefulWidget {
  final double weeklyNet;
  final int weeklyWords;
  final int habitCount;
  const CrossModuleAnalyticsWidget({super.key, required this.weeklyNet, required this.weeklyWords, required this.habitCount});
  @override
  State<CrossModuleAnalyticsWidget> createState() => _CrossModuleAnalyticsWidgetState();
}
class _CrossModuleAnalyticsWidgetState extends State<CrossModuleAnalyticsWidget> {
  List<FlSpot> _habitSpots = [];
  List<FlSpot> _writingSpots = [];
  List<FlSpot> _financeSpots = [];
  @override
  void initState(){ super.initState(); _loadCorrelation(); }
  Future<void> _loadCorrelation() async {
    try {
      final db = await DatabaseHelper.instance.database;
      List<FlSpot> hSpots = [], wSpots = [], fSpots = [];
      for(int i=6; i>=0; i--){
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final completions = await db.query('habit_completions', where: 'completed_date = ?', whereArgs: [dateStr]);
        final journals = await db.query('journal_entries', where: 'date = ?', whereArgs: [dateStr]);
        final txs = await db.query('transactions', where: 'date = ?', whereArgs: [dateStr]);
        int words = 0;
        for(var j in journals){ words += (j['content'] as String).split(RegExp(r'\s+')).length; }
        double net = 0;
        for(var t in txs){ final amt=(t['amount'] as num).toDouble(); net += t['type']=='Income'?amt:-amt; }
        hSpots.add(FlSpot((6-i).toDouble(), completions.length.toDouble()));
        wSpots.add(FlSpot((6-i).toDouble(), (words/100).clamp(0,10).toDouble()));
        fSpots.add(FlSpot((6-i).toDouble(), (net/50).clamp(-5,5).toDouble()));
      }
      if(!mounted) return;
      setState((){ _habitSpots=hSpots; _writingSpots=wSpots; _financeSpots=fSpots; });
    } catch(_){}
  }
  @override
  Widget build(BuildContext context){
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children:[
              const Icon(Icons.analytics_outlined, size: 18),
              const SizedBox(width:6),
              const Text('7-Day Correlation — Habits vs Writing vs Finance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, size:16), onPressed: _loadCorrelation),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v,meta){ const days=['6d','5d','4d','3d','2d','1d','Today']; final idx=v.toInt(); if(idx>=0&&idx<7) return Text(days[idx], style: const TextStyle(fontSize: 9)); return const Text(''); })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(spots: _habitSpots, isCurved: true, color: Colors.orange, barWidth: 2, dotData: FlDotData(show: true)),
                    LineChartBarData(spots: _writingSpots, isCurved: true, color: Colors.purple, barWidth: 2, dotData: FlDotData(show: true)),
                    LineChartBarData(spots: _financeSpots, isCurved: true, color: Colors.green, barWidth: 2, dotData: FlDotData(show: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children:[
              _legendDot('Habits', Colors.orange),
              _legendDot('Writing (words/100)', Colors.purple),
              _legendDot('Finance (net/50)', Colors.green),
            ]),
          ],
        ),
      ),
    );
  }
  Widget _legendDot(String label, Color c){ return Row(children:[Container(width:10,height:10,decoration:BoxDecoration(color:c, shape: BoxShape.circle)), const SizedBox(width:4), Text(label, style: const TextStyle(fontSize:10))]); }
}

class HabitHeatmapWidget extends StatefulWidget {
  const HabitHeatmapWidget({super.key});
  @override
  State<HabitHeatmapWidget> createState() => _HabitHeatmapWidgetState();
}
class _HabitHeatmapWidgetState extends State<HabitHeatmapWidget> {
  Map<String, int> _heatData = {};
  int _maxCount = 1;
  @override
  void initState(){ super.initState(); _loadHeatmap(); }
  Future<void> _loadHeatmap() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final start = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 42)));
      final completions = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [start]);
      Map<String,int> map={};
      for(var c in completions){ final d=c['completed_date'] as String; map[d]=(map[d]??0)+1; }
      int maxV = 1;
      if(map.isNotEmpty) maxV = map.values.reduce((a,b)=>a>b?a:b);
      if(!mounted) return;
      setState((){ _heatData=map; _maxCount=maxV>0?maxV:1; });
    } catch(_){}
  }
  @override
  Widget build(BuildContext context){
    final days = List.generate(42, (i)=>DateTime.now().subtract(Duration(days: 41-i)));
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children:[const Icon(Icons.calendar_view_month_outlined, size:18), const SizedBox(width:6), const Text('GitHub-Style Heatmap — 42 Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const Spacer(), IconButton(icon: const Icon(Icons.refresh, size:16), onPressed: _loadHeatmap)]),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 3, mainAxisSpacing: 3, childAspectRatio: 1),
              itemCount: 42,
              itemBuilder: (ctx, idx){
                final date = days[idx];
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final count = _heatData[dateStr] ?? 0;
                final intensity = (count/_maxCount).clamp(0.0,1.0);
                Color color;
                if(count==0) color = Colors.grey.shade200;
                else if(intensity<0.25) color = Colors.orange.shade100;
                else if(intensity<0.5) color = Colors.orange.shade300;
                else if(intensity<0.75) color = Colors.orange.shade600;
                else color = Colors.orange.shade800;
                return Tooltip(message: '$dateStr: $count', child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white, width: 0.5))));
              },
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text('42 days ago', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)), Text('Today — Max $_maxCount/day', style: TextStyle(fontSize: 9, color: Colors.grey.shade600))]),
          ],
        ),
      ),
    );
  }
}

class WeeklyReviewCard extends StatefulWidget {
  const WeeklyReviewCard({super.key});
  @override
  State<WeeklyReviewCard> createState() => _WeeklyReviewCardState();
}
class _WeeklyReviewCardState extends State<WeeklyReviewCard> {
  bool _generating = false;
  @override
  Widget build(BuildContext context){
    return Card(
      elevation: 2,
      color: Colors.indigo.shade50,
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: Colors.indigo),
        title: const Text('Weekly Life Review PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: const Text('Last 7 days — habits, tasks, finance, writing — local PDF', style: TextStyle(fontSize: 11)),
        trailing: _generating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('Generate'),
                onPressed: () async {
                  setState(()=>_generating=true);
                  await WeeklyReviewService.shareWeeklyPdf();
                  setState(()=>_generating=false);
                  if(mounted){
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Weekly PDF generated & share sheet opened',
                        ),
                      ),
                    );
                  }
                },
              ),
      ),
    );
  }
}

class P2PSyncCard extends StatefulWidget {
  const P2PSyncCard({super.key});
  @override
  State<P2PSyncCard> createState() => _P2PSyncCardState();
}
class _P2PSyncCardState extends State<P2PSyncCard> {
  String _ip = 'Loading...';
  bool _serving = false;
  final _ipController = TextEditingController();
  @override
  void initState(){ super.initState(); _loadIp(); }
  Future<void> _loadIp() async { final ip = await P2PSyncService.getLocalIp(); setState(()=>_ip=ip); }
  @override
  Widget build(BuildContext context){
    return Card(
      elevation: 2,
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children:[const Icon(Icons.sync_alt, size:18, color: Colors.teal), const SizedBox(width:6), const Text('P2P Sync — Local Wi-Fi (Zero Cloud)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const Spacer(), if(_serving) const Chip(label: Text('Serving', style: TextStyle(fontSize: 10)), backgroundColor: Colors.green, visualDensity: VisualDensity.compact)]),
            const SizedBox(height: 8),
            Text('This device IP: $_ip:8765 — Windows host starts server, iPhone 17 Pro Max enters IP to pull onyx_beacon.db directly over local Wi-Fi. No cloud, no fees.', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(children:[
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(_serving?Icons.stop:Icons.play_arrow),
                  label: Text(
                    _serving?'Stop Server':'Start Server (Host)',
                  ),
                  onPressed: () async {
                    if(_serving){
                      await P2PSyncService.stopServer();
                      setState(()=>_serving=false);
                    } else {
                      final ok = await P2PSyncService.startServer();
                      setState(()=>_serving=ok);
                      if(ok&&mounted){
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'P2P Server at http://$_ip:8765/db',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width:8),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.download), label: const Text('Sync From IP'), onPressed: ()=>_showSyncDialog())),
            ]),
          ],
        ),
      ),
    );
  }
  void _showSyncDialog(){
    showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('Sync from Host'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children:[
          const Text(
            'Enter Windows host IP (e.g., 192.168.1.15) — '
            'both devices same Wi-Fi, host must have Started Server',
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height:12),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Host IP',
              hintText: '192.168.1.15',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions:[
        TextButton(
          onPressed: ()=>Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final ip=_ipController.text.trim();
            if(ip.isNotEmpty){
              Navigator.pop(ctx);
              final ok = await P2PSyncService.syncFromServer(ip);
              if(mounted){
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ?'Sync success! Restart app. Backup saved.'
                          :'Sync failed — check IP & host server',
                    ),
                  ),
                );
              }
            }
          },
          child: const Text('Pull DB'),
        ),
      ],
    ));
  }
}

class AeroStatusCard extends StatelessWidget {
  final VoidCallback? onOpen;
  const AeroStatusCard({super.key, this.onOpen});
  @override
  Widget build(BuildContext context){
    final r = AeroRouter.instance;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => Card(
        elevation: 2,
        color: Colors.purple.shade50,
        child: ListTile(
          onTap: onOpen,
          leading: Icon(r.primary.icon, color: r.primary == AeroEngine.core ? Colors.blueGrey : Colors.green),
          title: const Text('AERO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          subtitle: Text(r.detecting ? 'Detecting engines…' : '${r.engineLabel} — tap to chat', style: const TextStyle(fontSize: 10)),
          trailing: IconButton(icon: const Icon(Icons.refresh, size: 18), tooltip: 'Re-detect', onPressed: () => r.detect(force: true)),
        ),
      ),
    );
  }
}

// ==================== 5. WRITING HUB — PUSH 4 KANBAN + AI COPILOT ====================
class JournalTab extends StatefulWidget {
  const JournalTab({super.key});
  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _filteredEntries = [];
  String _selectedFilter = 'All';
  String _selectedStatusFilter = 'All';
  String _searchQuery = '';
  bool _isKanbanView = false;
  final TextEditingController _searchController = TextEditingController();
  final List<String> _writingCategories = ['Book Chapter', 'Screenplay', 'Article', 'Short Story', 'Journal', 'Idea', 'Research'];
  final List<String> _moods = ['Focused', 'Inspired', 'Tired', 'Excited', 'Calm', 'Stressed', 'Reflective'];
  final List<String> _statuses = ['Idea','Drafting','Revision','Complete'];

  @override
  void initState(){
    super.initState();
    _refreshEntries();
  }

  Future<void> _refreshEntries() async {
    final entries = await DatabaseHelper.instance.getJournalEntries();
    setState((){ _entries = entries; });
    _applyFilters();
  }

  void _applyFilters(){
    List<Map<String, dynamic>> result = List.from(_entries);
    if(_selectedFilter != 'All'){ result = result.where((e)=>e['category']==_selectedFilter).toList(); }
    if(_selectedStatusFilter != 'All'){ result = result.where((e)=>(e['status']??'Idea')==_selectedStatusFilter).toList(); }
    if(_searchQuery.isNotEmpty){ result = result.where((e)=>(e['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase()) || (e['content'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList(); }
    result.sort((a,b)=> (a['order_index']??0).compareTo(b['order_index']??0));
    setState(()=>_filteredEntries=result);
  }

  Future<void> _updateStatus(int id, String newStatus) async {
    // Land at the bottom of the target column so ordering stays stable after restart.
    final inTarget = _entries.where((e)=>(e['status']??'Idea')==newStatus).map((e)=>(e['order_index'] as int?) ?? 0);
    final nextOrder = inTarget.isEmpty ? 0 : inTarget.reduce((a,b)=>a>b?a:b) + 1;
    await DatabaseHelper.instance.updateJournalEntry(id, {'status': newStatus, 'order_index': nextOrder});
    await _refreshEntries();
  }

  /// Renumber a whole column 0..n so order_index never collides and survives restarts.
  Future<void> _persistColumnOrder(List<Map<String, dynamic>> column) async {
    for(int i=0; i<column.length; i++){
      await DatabaseHelper.instance.updateJournalEntry(column[i]['id'] as int, {'order_index': i});
    }
  }

  void _openEditor({Map<String, dynamic>? entry}){
    final isEditing = entry != null;
    final titleController = TextEditingController(text: entry?['title'] ?? '');
    final contentController = TextEditingController(text: entry?['content'] ?? '');
    String selectedCategory = entry?['category'] ?? _writingCategories.first;
    String selectedMood = entry?['mood'] ?? _moods.first;
    String selectedStatus = entry?['status'] ?? 'Idea';
    bool isAiLoading = false;
    String aiResult = '';

    showDialog(
      context: context,
      builder: (context){
        return StatefulBuilder(
          builder: (context, setDialogState){
            return AlertDialog(
              title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
                Text(isEditing?'Edit Writing':'New Writing'),
                Row(children:[
                  IconButton(icon: const Icon(Icons.smart_toy_outlined, size:20), tooltip: 'AERO', onPressed: ()=>_showAiDialog(contentController, setDialogState)),
                  IconButton(icon: const Icon(Icons.category, size:20), onPressed: ()=>Navigator.pop(context)),
                ]),
              ]),
              content: SizedBox(
                width: 600,
                height: 520,
                child: Column(
                  children: [
                    Row(children:[
                      Expanded(flex:2, child: DropdownButtonFormField<String>(value: selectedCategory, decoration: const InputDecoration(labelText: 'Format / Type'), items: _writingCategories.map((cat)=>DropdownMenuItem(value: cat, child: Text(cat))).toList(), onChanged: (val){ if(val!=null) setDialogState(()=>selectedCategory=val); })),
                      const SizedBox(width:12),
                      Expanded(flex:2, child: DropdownButtonFormField<String>(value: selectedMood, decoration: const InputDecoration(labelText: 'State / Mood'), items: _moods.map((m)=>DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (val){ if(val!=null) setDialogState(()=>selectedMood=val); })),
                    ]),
                    const SizedBox(height:8),
                    DropdownButtonFormField<String>(value: selectedStatus, decoration: const InputDecoration(labelText: 'Status — Kanban'), items: _statuses.map((s)=>DropdownMenuItem(value:s, child: Row(children:[Icon(WritingStatusExt.fromString(s).icon, size:16), const SizedBox(width:6), Text(s)]))).toList(), onChanged: (val){ if(val!=null) setDialogState(()=>selectedStatus=val); }),
                    const SizedBox(height:12),
                    TextField(controller: titleController, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: 'Title / Chapter Name', hintText: 'Enter title...')),
                    const SizedBox(height:12),
                    Expanded(child: TextField(controller: contentController, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(labelText: 'Content / Draft / Thoughts', alignLabelWithHint: true, border: OutlineInputBorder(), hintText: 'Start writing your story, article, or thoughts here...'))),
                    if(aiResult.isNotEmpty)...[
                      const SizedBox(height:8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.purple.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:[
                            Row(children:[
                              const Icon(Icons.smart_toy, size:14),
                              const SizedBox(width:4),
                              const Text(
                                'AI Suggestion',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize:11,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: (){
                                  contentController.text +=
                                      '\n\n' + aiResult;
                                  setDialogState(()=>aiResult='');
                                },
                                child: const Text(
                                  'Insert',
                                  style: TextStyle(fontSize:10),
                                ),
                              ),
                            ]),
                            Text(
                              aiResult,
                              style: const TextStyle(fontSize:11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions:[
                TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(onPressed: () async {
                  final title = titleController.text.trim();
                  final content = contentController.text.trim();
                  if(title.isNotEmpty && content.isNotEmpty){
                    final wordCount = content.split(RegExp(r'\s+')).length;
                    final row = {'title': title, 'content': content, 'category': selectedCategory, 'mood': selectedMood, 'status': selectedStatus, 'date': isEditing ? (entry?['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())) : DateFormat('yyyy-MM-dd').format(DateTime.now()), 'color': entry?['color'] ?? '#9B59B6', 'word_count': wordCount, 'order_index': isEditing && entry?['status'] == selectedStatus ? (entry?['order_index'] ?? 0) : _entries.where((e)=>(e['status']??'Idea')==selectedStatus).length};
                    if(isEditing){ await DatabaseHelper.instance.updateJournalEntry(entry['id'], row); } else { await DatabaseHelper.instance.insertJournalEntry(row); }
                    await _refreshEntries();
                    if(mounted) Navigator.pop(context);
                  }
                }, child: Text(isEditing?'Save':'Add')),
              ],
            );
          },
        );
      },
    );
  }

  void _showAiDialog(TextEditingController contentCtrl, StateSetter parentSetState){
    final instructionCtrl = TextEditingController(text: 'Improve this writing, keep my voice, fix grammar');
    String aiResponse = '';
    AeroEngine? usedEngine;
    bool loading = false;
    showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx, setState){
      Future<void> run(String instruction) async {
        if(contentCtrl.text.trim().isEmpty || loading) return;
        setState(()=>loading=true);
        final reply = await AeroRouter.instance.assistWriting(instruction, contentCtrl.text);
        if(!ctx.mounted) return;
        setState((){ aiResponse=reply.text; usedEngine=reply.engine; loading=false; });
      }
      return AlertDialog(
        title: Text('AERO — ${AeroRouter.instance.primary.shortName}'),
        content: SizedBox(width: 400, height: 380, child: Column(children:[
          TextField(controller: instructionCtrl, decoration: const InputDecoration(labelText: 'Instruction', hintText: 'Improve, Summarize, Expand, Critique...')),
          const SizedBox(height:12),
          Wrap(spacing: 8, runSpacing: 4, children:[
            ElevatedButton(onPressed: () => run(instructionCtrl.text), child: const Text('Run AI')),
            TextButton(onPressed: () => run('Summarize this in 3 bullet points, keep key ideas'), child: const Text('Summarize')),
            TextButton(onPressed: () => run('Expand this with vivid detail, keep the same style'), child: const Text('Expand')),
            TextButton(onPressed: () => run('Critique this as an editor: strengths, weaknesses, 3 specific improvements'), child: const Text('Critique')),
          ]),
          const SizedBox(height:12),
          if(loading) const CircularProgressIndicator(),
          if(aiResponse.isNotEmpty) Expanded(child: SingleChildScrollView(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Text(aiResponse)))),
        ])),
        actions:[
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Close')),
          if(aiResponse.isNotEmpty && usedEngine != AeroEngine.core) ElevatedButton(onPressed: (){ contentCtrl.text = aiResponse; Navigator.pop(ctx); parentSetState((){}); }, child: const Text('Replace Content')),
          if(aiResponse.isNotEmpty && usedEngine != AeroEngine.core) ElevatedButton(onPressed: (){ contentCtrl.text += '\n\n$aiResponse'; Navigator.pop(ctx); parentSetState((){}); }, child: const Text('Append')),
        ],
      );
    }));
  }

  Widget _buildKanbanView(){
    // Phones: fixed-width columns you swipe between (4 columns in 390pt squeezed text to one letter per line).
    // Wide screens (Surface, iPad landscape): all four side by side.
    return LayoutBuilder(builder: (ctx, constraints){
      final wide = constraints.maxWidth >= 900;
      final columns = _statuses.map((status){
        final col = _buildKanbanColumn(status);
        return wide ? Expanded(child: col) : SizedBox(width: (constraints.maxWidth * 0.78).clamp(240.0, 320.0).toDouble(), child: col);
      }).toList();
      if(wide) return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(height: constraints.maxHeight, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns)),
      );
    });
  }

  Widget _buildKanbanColumn(String status){
        final statusEntries = _filteredEntries.where((e)=>(e['status']??'Idea')==status).toList();
        final statusEnum = WritingStatusExt.fromString(status);
        final headerText = statusEnum.color.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
        return Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: statusEnum.color.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusEnum.color)),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusEnum.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      topRight: Radius.circular(11),
                    ),
                  ),
                  child: Row(children:[
                    Icon(
                      statusEnum.icon,
                      size:16,
                      color: headerText,
                    ),
                    const SizedBox(width:4),
                    Text(
                      status,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: headerText,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${statusEntries.length}',
                      style: TextStyle(
                        color: headerText,
                        fontSize: 11,
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: statusEntries.length,
                    onReorder: (oldIdx, newIdx) async {
                      if(newIdx>oldIdx) newIdx--;
                      final column = List<Map<String,dynamic>>.from(statusEntries);
                      final moved = column.removeAt(oldIdx);
                      column.insert(newIdx, moved);
                      await _persistColumnOrder(column);
                      await _refreshEntries();
                    },
                    itemBuilder: (ctx, idx){
                      final entry = statusEntries[idx];
                      return Card(key: ValueKey(entry['id']), margin: const EdgeInsets.all(6), child: ListTile(
                        dense: true,
                        title: Text(entry['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text('${entry['category']} • ${entry['word_count']??0}w', style: const TextStyle(fontSize: 10)), const SizedBox(height:4), LinearProgressIndicator(value: _statuses.indexOf(status)/3, color: statusEnum.color, backgroundColor: Colors.grey.shade200, minHeight: 3)]),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v){
                            if(v=='edit'){
                              _openEditor(entry: entry);
                            } else if(v!=''&&_statuses.contains(v)){
                              _updateStatus(entry['id'], v);
                            }
                          },
                          itemBuilder: (c){
                            return [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuDivider(),
                              ..._statuses.where(
                                (s)=>s!=status
                              ).map(
                                (s)=>PopupMenuItem(
                                  value:s,
                                  child: Text('Move to $s'),
                                ),
                              ),
                            ];
                          },
                        ),
                        onTap: ()=>_openEditor(entry: entry),
                      ));
                    },
                  ),
                ),
              ],
            ),
        );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Hub & Micro-Journal'),
        actions: [
          IconButton(icon: Icon(_isKanbanView?Icons.view_list:Icons.view_kanban), tooltip: _isKanbanView?'List View':'Kanban Board', onPressed: ()=>setState(()=>_isKanbanView=!_isKanbanView)),
          IconButton(icon: const Icon(Icons.file_download), tooltip: 'Export JSON', onPressed: ()=>ExportService.exportJournalJson(_filteredEntries)),
          PopupMenuButton<String>(onSelected: (v){ if(v=='pdf') WeeklyReviewService.shareWeeklyPdf(); }, itemBuilder: (c)=>[const PopupMenuItem(value: 'pdf', child: Text('Weekly PDF Review'))]),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search by title, content, mood...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true), onChanged: (v){ _searchQuery=v; _applyFilters(); }),
          ),
          SizedBox(height: 60, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children:<Widget>[
            Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: const Text('All Categories'), selected: _selectedFilter=='All', onSelected: (s){ setState(()=>_selectedFilter='All'); _applyFilters(); })),
            ..._writingCategories.map((cat)=>Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: Text(cat), selected: _selectedFilter==cat, onSelected: (s){ setState(()=>_selectedFilter=cat); _applyFilters(); }))),
          ])),
          SizedBox(height: 50, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children:<Widget>[
            Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: const Text('All Status'), selected: _selectedStatusFilter=='All', onSelected: (s){ setState(()=>_selectedStatusFilter='All'); _applyFilters(); })),
            ..._statuses.map((st){
              final enumVal = WritingStatusExt.fromString(st);
              return Padding(
                padding: const EdgeInsets.only(right:8),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:[
                      Icon(enumVal.icon, size:14),
                      const SizedBox(width:4),
                      Text(st),
                    ],
                  ),
                  selected: _selectedStatusFilter==st,
                  onSelected: (s){
                    setState(()=>_selectedStatusFilter=st);
                    _applyFilters();
                  },
                  selectedColor: enumVal.color.withOpacity(0.3),
                ),
              );
            }),
          ])),
          const Divider(height:1),
          Expanded(child: _isKanbanView ? _buildKanbanView() : _filteredEntries.isEmpty ? const Center(child: Text('No writings found. Tap + to start. Switch to Kanban via top icon.')) : ListView.builder(padding: const EdgeInsets.only(bottom: 96), itemCount: _filteredEntries.length, itemBuilder: (ctx, idx){
            final entry = _filteredEntries[idx];
            final status = entry['status']??'Idea';
            final statusEnum = WritingStatusExt.fromString(status);
            return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: ListTile(
              leading: Container(width: 8, height: 40, decoration: BoxDecoration(color: statusEnum.color, borderRadius: BorderRadius.circular(4))),
              title: Text(entry['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                const SizedBox(height:4),
                Text(entry['content'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                const SizedBox(height:6),
                Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children:[
                  Chip(label: Text(entry['category'], style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  Chip(label: Text(status, style: const TextStyle(fontSize: 10)), backgroundColor: statusEnum.color.withOpacity(0.3), visualDensity: VisualDensity.compact, avatar: Icon(statusEnum.icon, size:12)),
                  Text('${entry['mood']} • ${entry['date']} • ${entry['word_count']??0}w', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ]),
              ]),
              isThreeLine: true,
              onTap: ()=>_openEditor(entry: entry),
              trailing: Row(mainAxisSize: MainAxisSize.min, children:[
                IconButton(icon: const Icon(Icons.smart_toy_outlined, size:18), tooltip: 'AERO', onPressed: (){ _openEditor(entry: entry); }),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red, size:18), onPressed: () async { await DatabaseHelper.instance.deleteJournalEntry(entry['id']); await _refreshEntries(); }),
              ]),
            ));
          })),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: ()=>_openEditor(), child: const Icon(Icons.add)),
    );
  }
}



// ==================== PUSH 5 — GALLERY (Take Pictures + Save in App + Phone Gallery) ====================
class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key});
  @override
  State<GalleryTab> createState() => _GalleryTabState();
}
class _GalleryTabState extends State<GalleryTab> {
  final ImagePicker _picker = ImagePicker();
  List<String> _images = [];
  @override
  void initState(){ super.initState(); _loadGallery(); }
  Future<void> _loadGallery() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final gDir = Directory(path.join(dir.path, 'AERO', 'gallery'));
      if(!await gDir.exists()) await gDir.create(recursive:true);
      final files = gDir.listSync().where((f){ final l=f.path.toLowerCase(); return l.endsWith(".jpg")||l.endsWith(".png")||l.endsWith(".jpeg"); }).toList();
      if(mounted) setState(()=>_images = files.map((e)=>e.path).toList()..sort((a,b)=>b.compareTo(a)));
    } catch(_){}
  }
  Future<void> _takePicture() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if(photo==null) return;
      final dir = await getApplicationDocumentsDirectory();
      final gDir = Directory(path.join(dir.path, 'AERO', 'gallery'));
      if(!await gDir.exists()) await gDir.create(recursive:true);
      final name = "onyx_cam_${DateTime.now().millisecondsSinceEpoch}.jpg";
      await File(photo.path).copy(path.join(gDir.path, name));
      await _loadGallery();
    } catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Camera: $e"))); }
  }
  // Camera exists only on phones. On Windows/macOS/Linux image_picker has no camera, so desktop
  // gets a file picker instead of a "Take Picture" button that can only fail.
  bool get _hasCamera => Platform.isIOS || Platform.isAndroid;

  Future<void> _pickFromPhone() async {
    try {
      final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
      if(img==null) return;
      final dir = await getApplicationDocumentsDirectory();
      final gDir = Directory(path.join(dir.path, 'AERO', 'gallery'));
      if(!await gDir.exists()) await gDir.create(recursive:true);
      final ext = path.extension(img.path).toLowerCase();
      final keepExt = (ext == '.png' || ext == '.jpeg' || ext == '.jpg') ? ext : '.jpg';
      final name = "onyx_${_hasCamera ? 'phone' : 'pc'}_${DateTime.now().millisecondsSinceEpoch}$keepExt";
      await File(img.path).copy(path.join(gDir.path, name));
      await _loadGallery();
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't add photo: $e")));
    }
  }
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text("Gallery"), actions:[
        if(_hasCamera) IconButton(icon: const Icon(Icons.photo_library), tooltip: "Add from phone gallery", onPressed: _pickFromPhone),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadGallery),
      ]),
      floatingActionButton: _hasCamera
          ? FloatingActionButton.extended(onPressed: _takePicture, icon: const Icon(Icons.camera_alt), label: const Text("Take Picture"))
          : FloatingActionButton.extended(onPressed: _pickFromPhone, icon: const Icon(Icons.add_photo_alternate), label: const Text("Add Photo")),
      body: _images.isEmpty ? Center(child: Text(_hasCamera
          ? "No pictures yet.\n• Take one with the camera\n• Or add from your photo library\nSaved offline in AERO/gallery"
          : "No pictures yet.\nTap Add Photo to pick an image file.\nSaved offline in AERO/gallery", textAlign: TextAlign.center)) :
      GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3, crossAxisSpacing:6, mainAxisSpacing:6), itemCount: _images.length, itemBuilder: (ctx,i)=>ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_images[i]), fit: BoxFit.cover))),
    );
  }
}

// ==================== PUSH 5 — GAMETAB — Flappy, Breakout, Space Shooter ONLY (No Snake) ====================
class GameTab extends StatefulWidget {
  const GameTab({super.key});
  @override State<GameTab> createState() => _GameTabState();
}
class _GameTabState extends State<GameTab> {
  String _sel = "Flappy Onyx";
  final List<String> games = ["Flappy Onyx","Breakout","Space Shooter"];
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text("Gaming — Arcade"), centerTitle: true),
      body: Column(children:[
        const SizedBox(height:12),
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal:12), child: Row(children: games.map<Widget>((g){ final sel = g==_sel; return Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: Text(g), selected: sel, selectedColor: Colors.black, labelStyle: TextStyle(color: sel?Colors.white:Colors.black), onSelected: (_)=>setState(()=>_sel=g))); }).toList())),
        Expanded(child: _buildGame()),
      ]),
    );
  }
  Widget _buildGame(){
    IconData icon; String desc;
    switch(_sel){
      case "Flappy Onyx": icon = Icons.flutter_dash; desc = "iPhone 17 Pro Max primary — tap to flap, dodge pillars. Offline ready."; break;
      case "Breakout": icon = Icons.grid_view; desc = "Breakout — classic brick breaker. Flame ready for next push."; break;
      case "Space Shooter": icon = Icons.rocket_launch; desc = "Space Shooter — defend Onyx Beacon. Coming soon."; break;
      default: icon = Icons.extension; desc = "More games coming — suggest in AERO!"; break;
    }
    return Center(child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black12)), child: Column(mainAxisSize: MainAxisSize.min, children:[Icon(icon, size:64), const SizedBox(height:12), Text(_sel, style: const TextStyle(fontSize:22, fontWeight: FontWeight.bold)), const SizedBox(height:8), Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)), const SizedBox(height:16), ElevatedButton.icon(icon: const Icon(Icons.play_arrow), label: const Text("Play Soon"), onPressed: (){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$_sel playable in next push — Flame ready."))); })])));
  }
}



// ==================== AERO TAB — iPhone first, auto engine, streaming, no nag banners ====================
class AiChatTab extends StatefulWidget {
  const AiChatTab({super.key});
  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final AeroRouter _router = AeroRouter.instance;
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _listening = false;
  int _lastCount = 0;
  String _lastTail = '';

  bool get _voiceSupported => Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _router.addListener(_onRouterChanged);
    _router.detect();
  }

  @override
  void dispose() {
    _router.removeListener(_onRouterChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    try { _speech.stop(); } catch (_) {}
    super.dispose();
  }

  void _onRouterChanged() {
    final msgs = _router.messages;
    final tail = msgs.isEmpty ? '' : msgs.last.text;
    if (msgs.length != _lastCount || tail.length != _lastTail.length) {
      _lastCount = msgs.length;
      _lastTail = tail;
      _scrollToBottom();
    }
  }

  String get _welcome =>
      'Hi Caleb — AERO here, iPhone-first. Right now I\'m using ${_router.engineLabel}.\n'
      'I pick automatically: Core (instant) → TinyLlama (offline, ~640 MB) → Apple Intelligence (15 Pro+, iOS 26) → Ollama (Surface).\n'
      'Instant without any model: "hi", "what time is it", "summarize my week", "habits left today", "my tasks".';

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _router.busy) return;
    if (_listening) _stopListening();
    _inputCtrl.clear();
    await _router.send(text);
  }

  Future<void> _startDownload() async {
    final ok = await AeroOnDeviceService.downloadModel();
    await _router.detect(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Offline model ready (${_router.modelSizeMB} MB) — AERO now answers with VPN on, no Surface needed.'
          : 'Download did not finish — check Wi-Fi and keep the app open, then tap Download again.'),
    ));
  }

  void _showAeroSettings() {
    final urlCtrl = TextEditingController(text: AeroSettings.ollamaUrl);
    final modelCtrl = TextEditingController(text: AeroSettings.ollamaModel);
    showDialog(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: _router,
        builder: (ctx, _) => AlertDialog(
          title: const Text('AERO Engines'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_router.engineLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${_router.deviceLabel} • ${DateFormat('h:mm a EEE MMM d').format(DateTime.now())}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ]),
              ),
              const SizedBox(height: 8),
              ...AeroArchitectureService.getEngines(_router).map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(e.ready ? Icons.check_circle : e.icon, size: 18, color: e.ready ? Colors.green : Colors.grey),
                    title: Text(e.name + (e.active ? '  • in use' : ''), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: Text(e.availability, style: TextStyle(fontSize: 10, color: e.ready ? Colors.green.shade700 : Colors.grey.shade600)),
                  )),
              const Divider(height: 20),
              ValueListenableBuilder<double?>(
                valueListenable: AeroOnDeviceService.downloadProgress,
                builder: (ctx, progress, _) {
                  if (progress != null) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      LinearProgressIndicator(value: progress > 0 ? progress : null),
                      const SizedBox(height: 4),
                      Text('${(progress * 100).toStringAsFixed(1)}% — keep Onyx Beacon open until it finishes', style: const TextStyle(fontSize: 10)),
                    ]);
                  }
                  if (_router.hasModel) {
                    return Row(children: [
                      Expanded(child: Text('TinyLlama: ${_router.modelSizeMB} MB on this device', style: const TextStyle(fontSize: 11))),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete', style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          await AeroOnDeviceService.deleteModel();
                          await _router.detect(force: true);
                        },
                      ),
                    ]);
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Download offline model (~640 MB, once)'),
                      onPressed: _startDownload,
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              const Text('Ollama on your Surface (optional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(controller: urlCtrl, style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(labelText: 'Ollama URL', hintText: 'http://192.168.1.15:11434', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 6),
              TextField(controller: modelCtrl, style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(labelText: 'Model', hintText: 'llama3', border: OutlineInputBorder(), isDense: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => _router.detect(force: true), child: Text(_router.detecting ? 'Checking…' : 'Re-check')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ElevatedButton(
              onPressed: () async {
                await AeroSettings.save(url: urlCtrl.text, model: modelCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                await _router.detect(force: true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAeroArchitecture() {
    showDialog(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: _router,
        builder: (ctx, _) => AlertDialog(
          title: const Text('AERO — 4-Engine Architecture'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Think of AERO like a car brand: AERO is the name on the dashboard, the memory and the SQLite brain. '
                  'The engine that talks is swapped automatically.', style: TextStyle(fontSize: 11)),
              const SizedBox(height: 10),
              ...AeroArchitectureService.getEngines(_router).map((e) => Card(
                    color: e.color.withValues(alpha: e.active ? 0.22 : 0.08),
                    child: ListTile(
                      leading: Icon(e.ready ? Icons.check_circle : e.icon, color: e.ready ? Colors.green : Colors.grey, size: 22),
                      title: Text(e.name + (e.active ? '  • in use' : ''), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.subtitle, style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: e.color)),
                        const SizedBox(height: 2),
                        Text(e.description, style: const TextStyle(fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(e.availability, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: e.ready ? Colors.green.shade700 : Colors.grey.shade700)),
                      ]),
                    ),
                  )),
              const SizedBox(height: 8),
              const Text('Order: Core shortcut → TinyLlama → Apple Intelligence → Ollama → Core. '
                  'If an engine fails mid-answer, the next one takes over without asking.', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    );
  }

  Future<void> _startListening() async {
    try {
      final avail = await _speech.initialize(
        onError: (e) { if (mounted) setState(() => _listening = false); },
        onStatus: (s) { if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false); },
      );
      if (!avail) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow Microphone and Speech Recognition for Onyx Beacon in Settings.')));
        }
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (res) { if (mounted) setState(() => _inputCtrl.text = res.recognizedWords); },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mic error: $e')));
      }
    }
  }

  void _stopListening() {
    try { _speech.stop(); } catch (_) {}
    if (mounted) setState(() => _listening = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Widget _statusChip() {
    return ValueListenableBuilder<double?>(
      valueListenable: AeroOnDeviceService.downloadProgress,
      builder: (ctx, progress, _) {
        final r = _router;
        String text;
        Color bg;
        IconData icon;
        Widget? action;
        if (progress != null) {
          text = 'Downloading offline model ${(progress * 100).toStringAsFixed(0)}% • keep app open';
          bg = Colors.blue.shade50;
          icon = Icons.downloading;
        } else if (r.hasModel) {
          text = '${r.modelSizeMB} MB on-device ready • VPN ON ok • offline';
          bg = Colors.green.shade50;
          icon = Icons.check_circle;
        } else if (r.appleAvailable) {
          text = 'Apple Intelligence on-device • private';
          bg = Colors.deepPurple.shade50;
          icon = Icons.auto_awesome;
        } else {
          text = 'Core instant • download ~640 MB once for full offline AI';
          bg = Colors.grey.shade100;
          icon = Icons.memory;
          action = TextButton(onPressed: _startDownload, child: const Text('Download', style: TextStyle(fontSize: 11)));
        }
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(icon, size: 14, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
              if (action != null) action,
            ]),
            if (progress != null) LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 2),
          ]),
        );
      },
    );
  }

  Widget _bubble(AeroMessage msg) {
    final isUser = msg.isUser;
    final waiting = msg.streaming && msg.text.isEmpty;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? Colors.black : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4), bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: Border.all(color: isUser ? Colors.black : Colors.grey.shade300),
        ),
        child: waiting
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_router.primary == AeroEngine.tinyllama ? 'Loading model… first answer can take ~20 s' : 'AERO thinking…',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(msg.text, style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 13)),
                if (!isUser && msg.engine != null) ...[
                  const SizedBox(height: 6),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(msg.engine!.icon, size: 11, color: Colors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(msg.engine!.shortName + (msg.note != null ? ' • ${msg.note}' : ''),
                          style: const TextStyle(fontSize: 9, color: Colors.grey)),
                    ),
                  ]),
                ],
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _router,
      builder: (context, _) {
        final msgs = _router.messages;
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AERO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(_router.detecting ? 'Detecting engines…' : _router.engineLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
            actions: [
              IconButton(icon: const Icon(Icons.auto_awesome, size: 18), tooltip: 'Architecture', onPressed: _showAeroArchitecture),
              IconButton(icon: const Icon(Icons.settings, size: 18), tooltip: 'Engines', onPressed: _showAeroSettings),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'clear') _router.clear();
                  if (v == 'detect') _router.detect(force: true);
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'detect', child: Text('Re-detect engines')),
                  PopupMenuItem(value: 'clear', child: Text('Clear chat')),
                ],
              ),
            ],
          ),
          body: Column(children: [
            _statusChip(),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length + 1,
                itemBuilder: (ctx, idx) {
                  if (idx == 0) return _bubble(AeroMessage(isUser: false, text: _welcome));
                  return _bubble(msgs[idx - 1]);
                },
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Ask AERO — Bible, habits, writing, time…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  if (_voiceSupported) ...[
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: _listening ? Colors.red : Colors.grey.shade200,
                      child: IconButton(
                        icon: Icon(_listening ? Icons.mic_off : Icons.mic, color: _listening ? Colors.white : Colors.black87, size: 18),
                        onPressed: () { if (_listening) { _stopListening(); } else { _startListening(); } },
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: _router.busy ? Colors.grey : Colors.black,
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 18), onPressed: _router.busy ? null : _send),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}
