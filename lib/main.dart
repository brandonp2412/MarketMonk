import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/bottom_nav.dart';
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
    // Defer notification to post-frame so it fires after the current build
    // phase completes. Without this, notifyListeners() fires as a microtask
    // during the dialog's exit-animation frame, marking AccountsPage dirty
    // mid-build and triggering _dependents.isEmpty assertions on the Overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  Future<void> renameAccount(String oldName, String newName) async {
    if (newName.isEmpty || accounts.contains(newName)) return;
    final dir = await getApplicationSupportDirectory();
    final oldFileName =
        oldName == 'Default' ? 'market-monk' : 'market-monk-$oldName';
    final isActive = activeAccount == oldName;
    if (isActive) await db.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final src = File(p.join(dir.path, '$oldFileName.sqlite$suffix'));
      final dst = File(p.join(dir.path, 'market-monk-$newName.sqlite$suffix'));
      if (await src.exists()) await src.rename(dst.path);
    }
    accounts = accounts.map((a) => a == oldName ? newName : a).toList();
    if (isActive) {
      activeAccount = newName;
      db = Database('market-monk-$newName');
      clearAllSyncCache();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    if (isActive) await prefs.setString('activeAccount', newName);
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
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
          colorScheme: (settings.systemColors
                  ? (darkDynamic ??
                      ColorScheme.fromSeed(
                        seedColor: settings.seedColor,
                        brightness: Brightness.dark,
                      ))
                  : ColorScheme.fromSeed(
                      seedColor: settings.seedColor,
                      brightness: Brightness.dark,
                    ))
              .copyWith(surface: settings.pureBlack ? Colors.black : null),
          useMaterial3: true,
        ),
        themeMode: settings.theme,
        home: const MyHomePage(),
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
  final _pageController = PageController();
  var _currentIndex = 0;

  static const _tabs = ['ChartPage', 'PortfolioPage', 'HoldingsPage'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              children: const [ChartPage(), PortfolioPage(), HoldingsPage()],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: BottomNav(
                tabs: _tabs,
                currentIndex: _currentIndex,
                onTap: (i) {
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                  setState(() => _currentIndex = i);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
