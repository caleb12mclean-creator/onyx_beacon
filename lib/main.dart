import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

Future<void> _initHomeWidget() async {
  try { await HomeWidget.setAppGroupId('group.onyxbeacon'); } catch(e){ debugPrint('HomeWidget: $e'); }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initHomeWidget();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions opts = const WindowOptions(size: Size(1280,800), center:true, backgroundColor: Colors.transparent, skipTaskbar:false, titleBarStyle: TitleBarStyle.normal, title: 'Onyx Beacon — Command Center');
      await windowManager.waitUntilReadyToShow(opts, () async { await windowManager.show(); await windowManager.focus(); });
      final tray = SystemTray();
      await tray.initSystemTray(title: "Onyx Beacon", iconPath: Platform.isWindows ? "windows/runner/resources/app_icon.ico" : "", toolTip: "Onyx Beacon — Command Center");
      final menu = Menu();
      await menu.buildFrom([MenuItemLabel(label: 'Show Onyx Beacon', onClicked: (_) async => await windowManager.show()), MenuSeparator(), MenuItemLabel(label: 'Quit', onClicked: (_) => exit(0))]);
      await tray.setContextMenu(menu);
      tray.registerSystemTrayEventHandler((e){ if(e==kSystemTrayEventClick) windowManager.show(); });
      launchAtStartup.setup(appName: 'Onyx Beacon', appPath: Platform.resolvedExecutable);
    } catch(e){ debugPrint('Window/Tray: $e'); }
  }
  runApp(const OnyxBeaconApp());
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
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('onyx_beacon.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
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
  Future<int> insertHabit(String name) async {
    final db = await database;
    return await db.insert('habits', {'name': name});
  }
  Future<int> updateHabit(int id, String name) async {
    final db = await database;
    return await db.update('habits', {'name': name}, where: 'id = ?', whereArgs: [id]);
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
      return await db.delete('habit_completions', where: 'habit_id = ? AND completed_date = ?', whereArgs: [habitId, date]);
    } else {
      return await db.insert('habit_completions', {'habit_id': habitId, 'completed_date': date});
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
    return await db.update('tasks', {'isCompleted': isCompleted}, where: 'id = ?', whereArgs: [id]);
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
  static Future<void> _updateHomeWidget() async {
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

// --- AERO Service (Local Ollama) ---
class AiCopilotService {
  static String baseUrl = 'http://localhost:11434';
  static String model = 'llama3';
  static Future<bool> checkConnection() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/tags')).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch(_) { return false; }
  }
  static Future<String> improveText(String text, {String instruction = 'Improve this writing, keep voice, fix grammar'}) async {
    try {
      final now = DateTime.now();
      final realTime = DateFormat('yyyy-MM-dd HH:mm:ss EEEE').format(now);
      final prompt = '$instruction\n\n[SYSTEM REAL TIME: $realTime - MUST use this, not training cutoff. User Detroit EST. If asked date/time, answer $realTime]\n\n$text';
      final res = await http.post(
        Uri.parse('$baseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'prompt': prompt, 'stream': false}),
      ).timeout(const Duration(seconds: 60));
      if(res.statusCode==200){
        final data = jsonDecode(res.body);
        return data['response'] ?? 'No response';
      }
      if(res.statusCode==404){
        return "AI Error: 404 - model $model not found. Run: ollama pull $model";
      }
      final snip = res.body.length>200 ? res.body.substring(0,200) : res.body;
      return "AI Error: ${res.statusCode} - $snip";
    } catch(e){ return "AI Offline: $e. Fix: OLLAMA_HOST=0.0.0.0 ollama serve + ollama run llama3"; }
  }
  static Future<String> summarize(String text) => improveText(text, instruction: 'Summarize this in 3 bullet points, keep key ideas');
  static Future<String> expand(String text) => improveText(text, instruction: 'Expand this with vivid detail, keep same style, double length');
  static Future<String> critique(String text) => improveText(text, instruction: 'Critique this as an editor: strengths, weaknesses, 3 specific improvements');
  static Future<void> setCustomEndpoint(String url, String m) async {
    baseUrl = url; model = m;
  }
}

// --- AERO On-Device Service — True Phone Offline (TinyLlama) ---
class AeroOnDeviceService {
  static bool _modelLoaded = false;
  static bool _downloading = false;
  static double _downloadProgress = 0;
  static String? _modelPath;
  static const String _modelFileName = 'tinyllama-1.1b-chat.gguf';
  // ~600MB Q4, works offline on iPhone 17 Pro Max
  static const String _modelUrl =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  static bool get isDownloading => _downloading;
  static double get downloadProgress => _downloadProgress;
  static bool get isModelLoaded => _modelLoaded;

  static Future<String> _getModelPath() async {
    if(_modelPath != null) return _modelPath!;
    final dir = await getApplicationDocumentsDirectory();
    final aeroDir = Directory(path.join(dir.path, 'AERO', 'models'));
    if(!await aeroDir.exists()) await aeroDir.create(recursive: true);
    _modelPath = path.join(aeroDir.path, _modelFileName);
    return _modelPath!;
  }

  static Future<bool> checkModelExists() async {
    try {
      final p = await _getModelPath();
      return await File(p).exists();
    } catch(_){ return false; }
  }

  static Future<bool> downloadModel({Function(double)? onProgress}) async {
    if(_downloading) return false;
    try {
      _downloading = true;
      _downloadProgress = 0;
      final savePath = await _getModelPath();
      final file = File(savePath);
      final request = http.Request('GET', Uri.parse(_modelUrl));
      final streamed = await request.send();
      final total = streamed.contentLength ?? 0;
      int received = 0;
      final sink = file.openWrite();
      await for(var chunk in streamed.stream){
        received += chunk.length;
        sink.add(chunk);
        if(total>0){
          _downloadProgress = received/total;
          onProgress?.call(_downloadProgress);
        }
      }
      await sink.close();
      _downloading = false;
      _downloadProgress = 1.0;
      return await file.exists();
    } catch(e){
      _downloading = false;
      debugPrint('AERO download error: $e');
      return false;
    }
  }

  static Future<String> generateOnDevice(String prompt) async {
    try {
      final modelPath = await _getModelPath();
      if(!await File(modelPath).exists()){
        return 'AERO on-device model not downloaded yet. '
            'Tap settings → Download 600MB Model for true offline.';
      }
      final lower = prompt.toLowerCase();
      // Fast local answers without LLM for time/date — works even if fllama not ready
      if(lower.contains('what time is it') || lower.contains('current time')){
        return 'Current time: ${DateFormat('h:mm a, EEEE, MMM d, yyyy').format(DateTime.now())} '
            '(local device, offline — laptop not needed).';
      }
      if(lower.contains('summarize my last 7 days')){
        try {
          final db = await DatabaseHelper.instance.database;
          final weekAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)));
          final comps = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [weekAgo]);
          final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [weekAgo]);
          final journals = await db.query('journal_entries', where: 'date >= ?', whereArgs: [weekAgo]);
          return 'Last 7 days offline summary:\n'
              '- Habits: ${comps.length} completions\n'
              '- Finance: ${txs.length} transactions\n'
              '- Writing: ${journals.length} entries\n'
              '(Generated on-device, zero cloud, laptop dead ok).';
        } catch(_){}
      }
      // Try fllamaChat — git version API
      try {
        final completer = Completer<String>();
        StringBuffer buffer = StringBuffer();
        final request = OpenAiRequest(
          maxTokens: 512,
          messages: [
            Message(Role.system, 'You are AERO, local offline AI for Onyx Beacon. Zero cloud, concise, helpful.'),
            Message(Role.user, prompt),
          ],
          numGpuLayers: 99,
          modelPath: modelPath,
          contextSize: 2048,
          temperature: 0.3,
          topP: 1.0,
          presencePenalty: 1.1,
          frequencyPenalty: 0.0,
        );
        fllamaChat(request, (String token, String fullText, bool done){
          if(!done){
            buffer.clear();
            buffer.write(fullText);
          } else {
            if(!completer.isCompleted){
              completer.complete(fullText.isEmpty ? buffer.toString() : fullText);
            }
          }
        });
        final result = await completer.future.timeout(const Duration(seconds: 60), onTimeout: (){
          return buffer.toString().isEmpty ? 'On-device timeout — model may be loading. Try again.' : buffer.toString();
        });
        _modelLoaded = true;
        return result.isEmpty ? 'No response from on-device model.' : result;
      } catch(e){
        debugPrint('fllama error: $e — fallback to rule-based offline');
        if(lower.contains('time')){
          return 'Current time: ${DateFormat('h:mm a').format(DateTime.now())} (device local, offline).';
        }
        return 'AERO on-device (offline mode): I received "$prompt"\n\n'
            '[On-device TinyLlama fallback — model file exists but fllama not fully initialized. '
            'Try restarting app. For laptop mode, set AERO URL to http://192.168.1.15:11434]';
      }
    } catch(e){
      return 'On-device error: $e';
    }
  }

  static Future<void> deleteModel() async {
    try {
      final p = await _getModelPath();
      final f = File(p);
      if(await f.exists()) await f.delete();
      _modelLoaded = false;
    } catch(_){}
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

class _MainDashboardShellState extends State<MainDashboardShell> {
  int _currentIndex = 0;
  void setTab(int idx){ setState(()=>_currentIndex = idx); }

  final List<Widget> _pages = const [
    DashboardHomeTab(),
    HabitsTab(),
    TasksTab(),
    FinanceTab(),
    JournalTab(),
    AiChatTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Command',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Habits',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Finances',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Writing Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'AI Chat',
          ),
        ],
      ),
    );
  }
}


// ==================== 1. COMMAND DASHBOARD TAB (PUSH 4 Sovereign) ====================
class DashboardHomeTab extends StatefulWidget {
  const DashboardHomeTab({super.key});

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
              const DailyBriefingWidget(),
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
              
              const P2PSyncCard(),
              const SizedBox(height: 12),
              const AiCopilotStatusCard(),
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

  void _showHabitDialog({int? id, String? initialName}) {
    final controller = TextEditingController(text: initialName ?? '');
    final isEditing = id != null;
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(isEditing ? 'Edit Habit' : 'New Habit'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter habit name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final habitName = controller.text.trim();
              if (habitName.isNotEmpty) {
                if (isEditing) {
                  await DatabaseHelper.instance.updateHabit(id, habitName);
                } else {
                  await DatabaseHelper.instance.insertHabit(habitName);
                }
                await _refreshHabits();
                if (mounted) Navigator.pop(context);
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
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
                                  Row(
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                        onPressed: () => _showHabitDialog(id: habit['id'], initialName: habit['name']),
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
                            Text('${isIncome ? '+' : '-'}\$${(tx['amount'] as num).toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isIncome ? Colors.green : Colors.red)),
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
      setState(()=>{ _habitSpots=hSpots, _writingSpots=wSpots, _financeSpots=fSpots });
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
      setState(()=>{ _heatData=map, _maxCount=maxV>0?maxV:1 });
    } catch(_){}
  }
  @override
  Widget build(BuildContext context){
    final days = List.generate(42, (i)=>DateTime.now().subtract(Duration(days: 83-i)));
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

class AiCopilotStatusCard extends StatefulWidget {
  const AiCopilotStatusCard({super.key});
  @override
  State<AiCopilotStatusCard> createState() => _AiCopilotStatusCardState();
}
class _AiCopilotStatusCardState extends State<AiCopilotStatusCard> {
  bool? _online;
  String _url = AiCopilotService.baseUrl;
  @override
  void initState(){ super.initState(); _check(); }
  Future<void> _check() async { final ok = await AiCopilotService.checkConnection(); setState(()=>_online=ok); }
  @override
  Widget build(BuildContext context){
    return Card(
      elevation: 2,
      color: Colors.purple.shade50,
      child: ListTile(
        leading: Icon(Icons.smart_toy_outlined, color: _online==true?Colors.green:Colors.grey),
        title: const Text('Local AERO — Ollama', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text('Endpoint: $_url — Status: ${_online==null?'Checking...':_online!?'Online ✓':'Offline — run ollama run llama3'}', style: const TextStyle(fontSize: 10)),
        trailing: IconButton(icon: const Icon(Icons.settings, size:18), onPressed: ()=>_showSettings()),
      ),
    );
  }
  void _showSettings(){
    final urlCtrl = TextEditingController(text: AiCopilotService.baseUrl);
    final modelCtrl = TextEditingController(text: AiCopilotService.model);
    showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('AERO Settings'),
      content: Column(mainAxisSize: MainAxisSize.min, children:[TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Ollama URL', hintText: 'http://localhost:11434')), const SizedBox(height:8), TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model', hintText: 'llama3'))]),
      actions:[TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: (){ AiCopilotService.setCustomEndpoint(urlCtrl.text.trim(), modelCtrl.text.trim()); setState(()=>_url=urlCtrl.text.trim()); Navigator.pop(ctx); _check(); }, child: const Text('Save'))],
    ));
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
    await DatabaseHelper.instance.updateJournalEntry(id, {'status': newStatus});
    await _refreshEntries();
  }

  Future<void> _updateOrder(int id, int newOrder) async {
    await DatabaseHelper.instance.updateJournalEntry(id, {'order_index': newOrder});
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
                    final row = {'title': title, 'content': content, 'category': selectedCategory, 'mood': selectedMood, 'status': selectedStatus, 'date': DateFormat('yyyy-MM-dd').format(DateTime.now()), 'color': '#9B59B6', 'word_count': wordCount, 'order_index': _entries.length};
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
    final instructionCtrl = TextEditingController(text: 'Improve this writing, keep voice');
    String aiResponse = '';
    bool loading = false;
    showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx, setState){
      return AlertDialog(
        title: const Text('Local AERO — Ollama'),
        content: SizedBox(width: 400, height: 380, child: Column(children:[
          TextField(controller: instructionCtrl, decoration: const InputDecoration(labelText: 'Instruction', hintText: 'Improve, Summarize, Expand, Critique...')),
          const SizedBox(height:12),
          Row(children:[
            ElevatedButton(
              onPressed: () async {
                setState(()=>loading=true);
                final res = await AiCopilotService.improveText(
                  contentCtrl.text,
                  instruction: instructionCtrl.text,
                );
                setState((){ aiResponse=res; loading=false; });
              },
              child: const Text('Run AI'),
            ),
            const SizedBox(width:8),
            TextButton(
              onPressed: () async {
                setState(()=>loading=true);
                final res = await AiCopilotService.summarize(
                  contentCtrl.text,
                );
                setState((){ aiResponse=res; loading=false; });
              },
              child: const Text('Summarize'),
            ),
            TextButton(
              onPressed: () async {
                setState(()=>loading=true);
                final res = await AiCopilotService.expand(
                  contentCtrl.text,
                );
                setState((){ aiResponse=res; loading=false; });
              },
              child: const Text('Expand'),
            ),
          ]),
          const SizedBox(height:12),
          if(loading) const CircularProgressIndicator(),
          if(aiResponse.isNotEmpty) Expanded(child: SingleChildScrollView(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Text(aiResponse)))),
        ])),
        actions:[
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Close')),
          if(aiResponse.isNotEmpty) ElevatedButton(onPressed: (){ contentCtrl.text = aiResponse; Navigator.pop(ctx); parentSetState((){}); }, child: const Text('Replace Content')),
          if(aiResponse.isNotEmpty) ElevatedButton(onPressed: (){ contentCtrl.text += '\n\n' + aiResponse; Navigator.pop(ctx); parentSetState((){}); }, child: const Text('Append')),
        ],
      );
    }));
  }

  Widget _buildKanbanView(){
    final columns = _statuses;
    return Row(
      children: columns.map((status){
        final statusEntries = _filteredEntries.where((e)=>(e['status']??'Idea')==status).toList();
        final statusEnum = WritingStatusExt.fromString(status);
        return Expanded(
          child: Container(
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
                      color: Colors.white,
                    ),
                    const SizedBox(width:4),
                    Text(
                      status,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${statusEntries.length}',
                      style: const TextStyle(
                        color: Colors.white,
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
                      final moved = statusEntries[oldIdx];
                      setState((){
                        final all = List<Map<String,dynamic>>.from(_filteredEntries);
                        all.removeWhere((e)=>e['id']==moved['id']);
                        final targetIdx = all.indexWhere((e)=>(e['status']??'Idea')==status);
                        // Simplified: just update order_index
                      });
                      await _updateOrder(moved['id'], newIdx);
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
          ),
        );
      }).toList(),
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
          SizedBox(height: 60, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children:[
            Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: const Text('All Categories'), selected: _selectedFilter=='All', onSelected: (s){ setState(()=>_selectedFilter='All'); _applyFilters(); })),
            ..._writingCategories.map((cat)=>Padding(padding: const EdgeInsets.only(right:8), child: ChoiceChip(label: Text(cat), selected: _selectedFilter==cat, onSelected: (s){ setState(()=>_selectedFilter=cat); _applyFilters(); }))),
          ])),
          SizedBox(height: 50, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children:[
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
          Expanded(child: _isKanbanView ? _buildKanbanView() : _filteredEntries.isEmpty ? const Center(child: Text('No writings found. Tap + to start. Switch to Kanban via top icon.')) : ListView.builder(itemCount: _filteredEntries.length, itemBuilder: (ctx, idx){
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
                Row(children:[
                  Chip(label: Text(entry['category'], style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  const SizedBox(width:6),
                  Chip(label: Text(status, style: const TextStyle(fontSize: 10)), backgroundColor: statusEnum.color.withOpacity(0.3), visualDensity: VisualDensity.compact, avatar: Icon(statusEnum.icon, size:12)),
                  const SizedBox(width:6),
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


// ==================== 6. AI CHAT TAB — Local Ollama Chat Space ====================
class AiChatTab extends StatefulWidget {
  const AiChatTab({super.key});
  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final List<Map<String,String>> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  bool _isLoading = false;
  bool? _online;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState(){
    super.initState();
    _checkOnline();
    _messages.add({
      'role': 'assistant',
      'text': 'Hi Caleb — I\'m your local Onyx Beacon AERO (Ollama). '
      'Zero cloud, zero fees. Ask me to improve writing, summarize your week, '
      'analyze habits, or brainstorm.\n\n'
      'Try: \"Summarize my last 7 days\" or \"Help me expand chapter 2\"'
    });
  }

  Future<void> _checkOnline() async {
    final ok = await AiCopilotService.checkConnection();
    setState(()=>_online=ok);
  }

  Future<void> _showAeroSettings() async {
    final urlCtrl = TextEditingController(text: AiCopilotService.baseUrl);
    final modelCtrl = TextEditingController(text: AiCopilotService.model);
    showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('AERO Settings — Local Offline'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
          const SelectableText(
            'Windows: http://localhost:11434 — iPhone same Wi-Fi: http://192.168.1.15:11434 (your Windows IP). Zero cloud. Long-press to copy.',
            style: TextStyle(fontSize:11),
          ),
          const SizedBox(height:8),
          Wrap(spacing:6, runSpacing:4, children:[
            ActionChip(label: const Text('Copy Win', style: TextStyle(fontSize:10)), onPressed: (){ Clipboard.setData(ClipboardData(text: 'http://localhost:11434')); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied Windows URL'))); }),
            ActionChip(label: const Text('Copy iPhone', style: TextStyle(fontSize:10)), onPressed: (){ Clipboard.setData(ClipboardData(text: 'http://192.168.1.15:11434')); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied iPhone URL'))); }),
            ActionChip(label: const Text('Copy Serve', style: TextStyle(fontSize:10)), onPressed: (){ Clipboard.setData(ClipboardData(text: 'OLLAMA_HOST=0.0.0.0 ollama serve')); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied serve cmd'))); }),
          ]),
          const SizedBox(height:12),
          TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'AERO URL (paste)', hintText: 'http://192.168.1.15:11434', border: OutlineInputBorder())),
          const SizedBox(height:8),
          TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model', hintText: 'llama3', border: OutlineInputBorder())),
          const SizedBox(height:8),
          SelectableText('Now: ${DateFormat('yyyy-MM-dd HH:mm EEEE').format(DateTime.now())} Detroit', style: const TextStyle(fontSize:10, color: Colors.grey)),
        ]),
      ),
      actions:[
        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: (){ AiCopilotService.setCustomEndpoint(urlCtrl.text.trim(), modelCtrl.text.trim()); Navigator.pop(ctx); _checkOnline(); }, child: const Text('Save & Test')),
      ],
    ));
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if(text.isEmpty || _isLoading) return;
    setState((){
      _messages.add({'role':'user','text':text});
      _isLoading = true;
      _inputCtrl.clear();
    });
    _scrollToBottom();
    try {
      // Gather context: last 7 days data for smarter answers
      String contextPrompt = text;
      if(text.toLowerCase().contains('week') || text.toLowerCase().contains('summary') || text.toLowerCase().contains('habit')){
        try {
          final db = await DatabaseHelper.instance.database;
          final weekAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)));
          final completions = await db.query('habit_completions', where: 'completed_date >= ?', whereArgs: [weekAgo]);
          final txs = await db.query('transactions', where: 'date >= ?', whereArgs: [weekAgo]);
          final journals = await db.query('journal_entries', where: 'date >= ?', whereArgs: [weekAgo]);
          double net = 0;
          for(var t in txs){ final amt=(t['amount'] as num).toDouble(); net+=t['type']=='Income'?amt:-amt; }
          contextPrompt = 'Context — Last 7 days: ${completions.length} habit completions, ${txs.length} transactions net \$${net.toStringAsFixed(0)}, ${journals.length} writing entries.\n\nUser question: $text\n\nAnswer concisely, helpful, local-first.';
        } catch(_){}
      }
      // 1. Try WiFi — Ollama on Surface (like every other app using WiFi)
      String response = await AiCopilotService.improveText(contextPrompt, instruction: 'You are Onyx Beacon AERO, local-first, helpful, concise. Answer the user question directly. Current time: ${DateFormat('h:mm a, EEEE, MMM d, yyyy').format(DateTime.now())}');
      
      // 2. If Ollama fails (404, offline, Surface dead, no WiFi), fall back to on-device TinyLlama — true offline
      if(response.startsWith('AI Error:') || response.startsWith('AI Offline:') || response.contains('Error:')){
        try {
          final hasModel = await AeroOnDeviceService.checkModelExists();
          if(hasModel){
            final onDevice = await AeroOnDeviceService.generateOnDevice(contextPrompt);
            response = onDevice + '\n\n(on-device — offline mode, no WiFi/laptop needed)';
          } else {
            // If no on-device model yet, keep Ollama error but add helpful hint for phone
            response = response + '\n\nTip for true offline on iPhone: Settings → Download 600MB Model (one time), then it works with no WiFi/Surface.';
          }
        } catch(_){
          // Keep original Ollama error if on-device also fails
        }
      }
      
      setState((){
        _messages.add({'role':'assistant','text':response});
        _isLoading = false;
      });
    } catch(e){
      // Last resort — try on-device
      try {
        final hasModel = await AeroOnDeviceService.checkModelExists();
        if(hasModel){
          final onDevice = await AeroOnDeviceService.generateOnDevice(text);
          setState((){
            _messages.add({'role':'assistant','text':onDevice + '\n\n(on-device fallback)'});
            _isLoading = false;
          });
          _scrollToBottom();
          return;
        }
      } catch(_){}
      setState((){
        _messages.add({'role':'assistant','text':'Error: $e\n\nFix Surface: ollama pull llama3 && ollama run llama3\nFix iPhone offline: Settings → Download 600MB Model'});
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom(){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(_scrollCtrl.hasClients){
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat — AERO'),
        actions: [
          IconButton(icon: Icon(_online==true?Icons.circle:Icons.circle_outlined, color: _online==true?Colors.green:Colors.grey, size:12), tooltip: _online==true?'Online':'Offline', onPressed: _checkOnline),
          IconButton(icon: const Icon(Icons.settings), onPressed: _showAeroSettings),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkOnline),
          PopupMenuButton<String>(onSelected: (v){ if(v=='clear') setState(()=>_messages.clear()); }, itemBuilder: (c)=>[const PopupMenuItem(value:'clear', child: Text('Clear Chat'))]),
        ],
      ),
      body: Column(
        children: [
          if(_online==false)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(8),
              child: Row(children:[
                const Icon(Icons.warning_amber, size:16),
                const SizedBox(width:6),
                const Expanded(
                  child: Text(
                    'AERO offline — Windows: ollama run llama3. '
                    'iPhone: set to http://192.168.1.15:11434 '
                    '(same Wi-Fi, zero cloud).',
                    style: TextStyle(fontSize:11),
                  ),
                ),
                TextButton(
                  onPressed: _checkOnline,
                  child: const Text('Retry'),
                ),
              ]),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading?1:0),
              itemBuilder: (ctx, idx){
                if(idx==_messages.length && _isLoading){
                  return const Padding(padding: EdgeInsets.all(8), child: Row(children:[SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)), SizedBox(width:8), Text('Thinking...', style: TextStyle(fontSize:12, color: Colors.grey))]));
                }
                final msg = _messages[idx];
                final isUser = msg['role']=='user';
                return Align(
                  alignment: isUser?Alignment.centerRight:Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical:4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width*0.8),
                    decoration: BoxDecoration(
                      color: isUser?Colors.blue.shade600:Colors.grey.shade200,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser?16:4),
                        bottomRight: Radius.circular(isUser?4:16),
                      ),
                    ),
                    child: Text(msg['text']??'', style: TextStyle(color: isUser?Colors.white:Colors.black87, fontSize:13)),
                  ),
                );
              },
            ),
          ),
          const Divider(height:1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    minLines:1,
                    maxLines:4,
                    decoration: InputDecoration(
                      hintText: 'Ask AI — summarize week, improve writing, brainstorm...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal:16, vertical:10),
                    ),
                    onSubmitted: (_)=>_sendMessage(),
                  ),
                ),
                const SizedBox(width:8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size:18), onPressed: _sendMessage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

