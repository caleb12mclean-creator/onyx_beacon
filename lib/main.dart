import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

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
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A4E69),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainDashboardShell(),
    );
  }
}

// ==================== DATABASE HELPER ====================
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
      version: 4,
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
    }
  }

  // --- Habits CRUD ---
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
    return await db.delete('habits', where: 'id = ?', whereArgs: [id]);
  }

  // --- Tasks CRUD ---
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

  // --- Finance Categories CRUD ---
  Future<List<Map<String, dynamic>>> getFinanceCategories(String type) async {
    final db = await database;
    return await db.query('finance_categories', where: 'type = ?', whereArgs: [type]);
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

  // --- Transactions (Finance) CRUD ---
  Future<List<Map<String, dynamic>>> getTransactions() async {
    final db = await database;
    return await db.query('transactions', orderBy: 'id DESC');
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

  // --- Journal & Writing Studio CRUD ---
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

// ==================== 1. COMMAND DASHBOARD TAB ====================
class DashboardHomeTab extends StatelessWidget {
  const DashboardHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onyx Beacon — Command Center')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Welcome back, Commander.',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: const [
              MetricCard(title: 'Active Modules', value: 'All 5 Operational', icon: Icons.bolt, color: Colors.orange),
              MetricCard(title: 'Writing Studio', value: 'Books & Stories', icon: Icons.menu_book, color: Colors.purple),
              MetricCard(title: 'Finance Ledger', value: 'Dynamic Budgets', icon: Icons.account_balance_wallet, color: Colors.green),
              MetricCard(title: 'Database Engine', value: 'SQLite v4 Live', icon: Icons.storage, color: Colors.blue),
            ],
          ),
        ],
      ),
    );
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

// ==================== 2. HABITS TAB ====================
class HabitsTab extends StatefulWidget {
  const HabitsTab({super.key});

  @override
  State<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends State<HabitsTab> {
  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    _refreshHabits();
  }

  Future<void> _refreshHabits() async {
    final habits = await DatabaseHelper.instance.getHabits();
    setState(() {
      _habits = habits;
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
                Navigator.pop(context);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Onyx Beacon Habits')),
      body: _habits.isEmpty
          ? const Center(child: Text('No habits recorded yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: _habits.length,
              itemBuilder: (context, index) {
                final habit = _habits[index];
                return ListTile(
                  title: Text(habit['name']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showHabitDialog(id: habit['id'], initialName: habit['name']),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await DatabaseHelper.instance.deleteHabit(habit['id']);
                          await _refreshHabits();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showHabitDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==================== 3. TASKS TAB ====================
class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  List<Map<String, dynamic>> _tasks = [];

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
                Navigator.pop(context);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks & To-dos')),
      body: _tasks.isEmpty
          ? const Center(child: Text('No tasks recorded yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==================== 4. FINANCE TAB ====================
class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _incomeCategories = [];

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
    } catch (e) {
      setState(() {
        _transactions = [];
        _expenseCategories = [];
        _incomeCategories = [];
      });
    }
  }

  double get _totalIncome {
    return _transactions
        .where((t) => t['type'] == 'Income')
        .fold(0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
  }

  double get _totalExpense {
    return _transactions
        .where((t) => t['type'] == 'Expense')
        .fold(0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
  }

  double get _netBalance => _totalIncome - _totalExpense;

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
                      const TabBar(
                        tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')],
                      ),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
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
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: 'New $type category'),
              ),
            ),
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
                                    Navigator.pop(ctx);
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
    
    String selectedCategory = isEditing 
        ? transaction['category'] 
        : (availableCats.isNotEmpty ? availableCats.first['name'] : 'General');
    
    String selectedDate = isEditing 
        ? transaction['date'] 
        : DateTime.now().toIso8601String().substring(0, 10);

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
                mainAxisAlignment: MainAxisAlignment.between,
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
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title / Merchant', hintText: 'e.g., Grocery Store, Client Payment'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount (\$)', hintText: '0.00'),
                    ),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;

                    if (title.isNotEmpty && amount > 0) {
                      final row = {
                        'title': title,
                        'amount': amount,
                        'type': selectedType,
                        'category': selectedCategory,
                        'date': selectedDate,
                      };

                      if (isEditing) {
                        await DatabaseHelper.instance.updateTransaction(transaction['id'], row);
                      } else {
                        await DatabaseHelper.instance.insertTransaction(row);
                      }

                      await _refreshFinanceData();
                      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Ledger & Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage Categories',
            onPressed: _manageCategoriesDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Net Balance', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    '\$${_netBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _netBalance >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Income', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('+\$${_totalIncome.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Container(height: 30, width: 1, color: Colors.grey.shade300),
                      Column(
                        children: [
                          const Text('Expenses', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('-\$${_totalExpense.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions recorded. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isIncome = tx['type'] == 'Income';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isIncome ? Colors.green.shade100 : Colors.red.shade100,
                          child: Icon(
                            isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isIncome ? Colors.green : Colors.red,
                          ),
                        ),
                        title: Text(tx['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${tx['category']} • ${tx['date']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isIncome ? '+' : '-'}\$${(tx['amount'] as num).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                              onPressed: () => _showTransactionDialog(transaction: tx),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () async {
                                await DatabaseHelper.instance.deleteTransaction(tx['id']);
                                await _refreshFinanceData();
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
        onPressed: () => _showTransactionDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==================== 5. JOURNAL & WRITING STUDIO TAB ====================
class JournalTab extends StatefulWidget {
  const JournalTab({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  List<Map<String, dynamic>> _entries = [];
  String _selectedFilter = 'All';

  final List<String> _writingCategories = [
    'Daily Reflection',
    'Thought / Idea',
    'Article',
    'Short Story',
    'Book Chapter',
    'Screenplay'
  ];

  final List<String> _moods = [
    '⚡ Creative',
    '🔥 Focused',
    '✨ Inspired',
    '😌 Calm',
    '🌧️ Reflective',
    '🔋 Exhausted'
  ];

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
    } catch (e) {
      setState(() {
        _entries = [];
      });
    }
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
                    final row = {
                      'title': title,
                      'content': content,
                      'category': selectedCategory,
                      'mood': selectedMood,
                      'date': dateStr,
                    };

                    if (isEditing) {
                      await DatabaseHelper.instance.updateJournalEntry(entry['id'], row);
                    } else {
                      await DatabaseHelper.instance.insertJournalEntry(row);
                    }

                    await _refreshEntries();
                    Navigator.pop(context);
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
                        items: _writingCategories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
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
                        items: _moods.map((m) {
                          return DropdownMenuItem(value: m, child: Text(m));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) selectedMood = val;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(labelText: 'Title / Chapter Name', hintText: 'Enter title...'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Content / Draft / Thoughts',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      hintText: 'Start writing your story, article, or thoughts here...',
                    ),
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
    final filteredEntries = _selectedFilter == 'All' 
        ? _entries 
        : _entries.where((e) => e['category'] == _selectedFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Hub & Micro-Journal'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedFilter == 'All',
                    onSelected: (selected) => setState(() => _selectedFilter = 'All'),
                  ),
                ),
                ..._writingCategories.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedFilter == cat,
                      onSelected: (selected) => setState(() => _selectedFilter = cat),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filteredEntries.isEmpty
                ? const Center(child: Text('No writings or journal entries found. Tap + to start drafting.'))
                : ListView.builder(
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(entry['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                entry['content'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Chip(
                                    label: Text(entry['category'], style: const TextStyle(fontSize: 10)),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${entry['mood']} • ${entry['date']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () => _openEditor(entry: entry),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              await DatabaseHelper.instance.deleteJournalEntry(entry['id']);
                              await _refreshEntries();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}