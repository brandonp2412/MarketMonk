import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final theme = prefs.getString('theme');

  ThemeMode themeMode;
  switch (theme) {
    case 'ThemeMode.system':
      themeMode = ThemeMode.system;
      break;
    case 'ThemeMode.dark':
      themeMode = ThemeMode.dark;
      break;
    case 'ThemeMode.light':
      themeMode = ThemeMode.light;
      break;
    default:
      themeMode = ThemeMode.system;
      break;
  }

  final settings = SettingsState(themeMode);
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MyApp(),
    ),
  );
}

Database db = Database();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MarketMonk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B7A78)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B7A78),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: settings.theme,
      home: const MyHomePage(),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).colorScheme.surface,
        statusBarColor: Theme.of(context).colorScheme.surface,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: const DefaultTabController(
        length: 2,
        child: Scaffold(
          body: SafeArea(
            child: TabBarView(
              children: [
                ChartPage(),
                PortfolioPage(),
              ],
            ),
          ),
          bottomNavigationBar: TabBar(
            dividerColor: Colors.transparent,
            tabs: [
              Tab(
                icon: Icon(Icons.insights),
                text: "Charts",
              ),
              Tab(
                icon: Icon(Icons.pie_chart),
                text: "Portfolio",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
