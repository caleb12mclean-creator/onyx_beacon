import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

void main() {
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
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
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
        type TEXT NOT NULL
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
        date TEXT NOT NULL
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

// ==================== EXPORT UTILITY ====================
class ExportService {
  static Future<void> exportJson(String fileName, dynamic data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, fileName));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      await Share.shareXFiles([XFile(file.path)], text: 'Onyx Beacon Export: $fileName');
    } catch (e) {
      debugPrint('Export JSON error: $e');
    }
  }

  static Future<void> exportTransactionsCsv(List<Map<String, dynamic>> txs) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'transactions_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      final file = File(path.join(dir.path, fileName));
      final buffer = StringBuffer();
      buffer.writeln('id,title,amount,type,category,date');
      for (var tx in txs) {
        buffer.writeln('${tx['id']},"${tx['title']}",${tx['amount']},${tx['type']},${tx['category']},${tx['date']}');
      }
      await file.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Onyx Beacon Finance CSV');
    } catch (e) {
      debugPrint('Export CSV error: $e');
    }
  }

  static Future<void> exportJournalJson(List<Map<String, dynamic>> entries) async {
    final fileName = 'writing_hub_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    await exportJson(fileName, entries);
  }

  static Future<void> exportFullBackup() async {
    final allData = await DatabaseHelper.instance.getAllDataForExport();
    final Map<String, dynamic> backup = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': 5,
      'tables': {for (var t in allData) t['table'] as String: t['data']}
    };
    final fileName = 'onyx_beacon_full_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
    await exportJson(fileName, backup);
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

  final List<Widget> _pages = const [
    DashboardHomeTab(),
    HabitsTab(),
    TasksTab(),
    FinanceTab(),
    JournalTab(),
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
        ],
      ),
    );
  }
}

// ==================== 1. COMMAND DASHBOARD TAB (with Global Search) ====================
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

  @override
  void initState() {
    super.initState();
    _loadCounts();
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

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
      });
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
          IconButton(
            icon: const Icon(Icons.backup_outlined),
            tooltip: 'Full Backup JSON',
            onPressed: () => ExportService.exportFullBackup(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Welcome back, Caleb.',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Global search: habits, tasks, finance, writing...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _doSearch('');
                      },
                    )
                  : null,
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
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              MetricCard(title: 'Habits', value: '$_habitCount Tracked', icon: Icons.bolt, color: Colors.orange),
              MetricCard(title: 'Tasks', value: '$_taskCount Active', icon: Icons.task_alt, color: Colors.blue),
              MetricCard(title: 'Finance Ledger', value: '$_txCount Transactions', icon: Icons.account_balance_wallet, color: Colors.green),
              MetricCard(title: 'Writing Studio', value: '$_journalCount Drafts', icon: Icons.menu_book, color: Colors.purple),
              MetricCard(title: 'Database Engine', value: 'SQLite v5 Live', icon: Icons.storage, color: Colors.indigo),
              MetricCard(title: 'Export Center', value: 'JSON / CSV Ready', icon: Icons.file_download, color: Colors.teal),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Quick Export'),
              subtitle: const Text('Backup entire vault as JSON'),
              trailing: ElevatedButton(
                onPressed: () => ExportService.exportFullBackup(),
                child: const Text('Export'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSearchResults() {
    if (_searchResults == null) return [];
    final List<Widget> widgets = [];
    _searchResults!.forEach((key, list) {
      if (list.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('$key: ${list.length} found', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ));
        for (var item in list.take(3)) {
          String title = item['name'] ?? item['title'] ?? 'Untitled';
          widgets.add(ListTile(
            dense: true,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(key),
            leading: const Icon(Icons.search, size: 16),
          ));
        }
      }
    });
    if (widgets.isEmpty) {
      widgets.add(const ListTile(title: Text('No results found')));
    }
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
                                  Expanded(
                                    child: Text(habit['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
class JournalTab extends StatefulWidget {
  const JournalTab({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _filteredEntries = [];
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<String> _writingCategories = ['Daily Reflection', 'Thought / Idea', 'Article', 'Short Story', 'Book Chapter', 'Screenplay'];
  final List<String> _moods = ['⚡ Creative', '🔥 Focused', '✨ Inspired', '😌 Calm', '🌧 Reflective', '🔋 Exhausted'];

  @override
  void initState() {
    super.initState();
    _refreshEntries();
  }

  Future<void> _refreshEntries() async {
    try {
      final entries = await DatabaseHelper.instance.getJournalEntries();
      setState(() {
        _entries = entries;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _entries = [];
        _filteredEntries = [];
      });
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_entries);
    if (_selectedFilter != 'All') {
      result = result.where((e) => e['category'] == _selectedFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result.where((e) => (e['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase()) || (e['content'] as String).toLowerCase().contains(_searchQuery.toLowerCase()) || (e['mood'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    setState(() {
      _filteredEntries = result;
    });
  }

  void _openEditor({Map<String, dynamic>? entry}) {
    final isEditing = entry != null;
    final titleController = TextEditingController(text: isEditing ? entry['title'] : '');
    final contentController = TextEditingController(text: isEditing ? entry['content'] : '');
    String selectedCategory = isEditing ? entry['category'] : _writingCategories.first;
    String selectedMood = isEditing ? entry['mood'] : _moods.first;
    String dateStr = isEditing ? entry['date'] : DateTime.now().toIso8601String().substring(0, 10);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Writing / Entry' : 'New Writing Studio Entry'),
            actions: [
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  final title = titleController.text.trim();
                  final content = contentController.text.trim();
                  if (title.isNotEmpty && content.isNotEmpty) {
                    final row = {'title': title, 'content': content, 'category': selectedCategory, 'mood': selectedMood, 'date': dateStr};
                    if (isEditing) {
                      await DatabaseHelper.instance.updateJournalEntry(entry['id'], row);
                    } else {
                      await DatabaseHelper.instance.insertJournalEntry(row);
                    }
                    await _refreshEntries();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Format / Type'),
                        items: _writingCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                        onChanged: (val) {
                          if (val != null) selectedCategory = val;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: selectedMood,
                        decoration: const InputDecoration(labelText: 'State / Mood'),
                        items: _moods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: (val) {
                          if (val != null) selectedMood = val;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: titleController, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: 'Title / Chapter Name', hintText: 'Enter title...')),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(labelText: 'Content / Draft / Thoughts', alignLabelWithHint: true, border: OutlineInputBorder(), hintText: 'Start writing your story, article, or thoughts here...'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Hub & Micro-Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Writing Hub JSON',
            onPressed: () => ExportService.exportJournalJson(_filteredEntries),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(hintText: 'Search by title, content, mood...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true),
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(label: const Text('All'), selected: _selectedFilter == 'All', onSelected: (selected) { setState(() => _selectedFilter = 'All'); _applyFilters(); }),
                ),
                ..._writingCategories.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedFilter == cat,
                      onSelected: (selected) {
                        setState(() => _selectedFilter = cat);
                        _applyFilters();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filteredEntries.isEmpty
                ? const Center(child: Text('No writings or journal entries found. Tap + to start drafting.'))
                : ListView.builder(
                    itemCount: _filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _filteredEntries[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(entry['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(entry['content'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Chip(label: Text(entry['category'], style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                  const SizedBox(width: 8),
                                  Text('${entry['mood']} • ${entry['date']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () => _openEditor(entry: entry),
                          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await DatabaseHelper.instance.deleteJournalEntry(entry['id']); await _refreshEntries(); }),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _openEditor(), child: const Icon(Icons.add)),
    );
  }
}
