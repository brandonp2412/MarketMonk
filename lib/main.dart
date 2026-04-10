import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsState();
  final accounts = AccountManager();
  await accounts.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: const MyApp(),
    ),
  );
}

Database db = Database();

/// Manages named portfolio accounts backed by separate SQLite files.
/// Switching accounts has zero per-query overhead — only the DB file changes.
class AccountManager extends ChangeNotifier {
  List<String> accounts = ['Default'];
  String activeAccount = 'Default';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    activeAccount = prefs.getString('activeAccount') ?? 'Default';
    accounts = prefs.getStringList('accounts') ?? ['Default'];
    if (activeAccount != 'Default') {
      db = Database('market-monk-$activeAccount');
    }
  }

  Future<void> switchAccount(String name) async {
    if (name == activeAccount) return;
    await db.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeAccount', name);
    activeAccount = name;
    db = name == 'Default' ? Database() : Database('market-monk-$name');
    clearAllSyncCache();
    notifyListeners();
  }

  Future<void> addAccount(String name) async {
    if (accounts.contains(name)) return;
    accounts = [...accounts, name];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    notifyListeners();
  }

  Future<void> deleteAccount(String name) async {
    if (name == 'Default') return;
    if (activeAccount == name) await switchAccount('Default');
    accounts = accounts.where((a) => a != name).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'market-monk-$name.sqlite'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        title: 'MarketMonk',
        theme: ThemeData(
          colorScheme: settings.systemColors
              ? lightDynamic
              : ColorScheme.fromSeed(seedColor: settings.seedColor),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: settings.systemColors
              ? darkDynamic
              : ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.dark,
                ),
          useMaterial3: true,
        ),
        themeMode: settings.theme,
        // ValueKey forces a full rebuild when the active account changes,
        // ensuring all tabs reload their data from the new database.
        home: MyHomePage(key: ValueKey(accounts.activeAccount)),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
    return const DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: TabBarView(
            children: [
              ChartPage(),
              PortfolioPage(),
              HoldingsPage(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: TabBar(
            dividerColor: Colors.transparent,
            tabs: [
              Tab(icon: Icon(Icons.insights), text: "Charts"),
              Tab(icon: Icon(Icons.pie_chart), text: "Portfolio"),
              Tab(icon: Icon(Icons.list_alt), text: "Holdings"),
            ],
          ),
        ),
      ),
    );
  }
}
