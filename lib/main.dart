import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsState();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MyApp(),
    ),
  );
}

Database db = Database();

final defaultTheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2B7A78));
final defaultDark = ColorScheme.fromSeed(
  seedColor: const Color(0xFF2B7A78),
  brightness: Brightness.dark,
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        title: 'MarketMonk',
        theme: ThemeData(
          colorScheme: settings.systemColors ? lightDynamic : defaultTheme,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: settings.systemColors ? darkDynamic : defaultDark,
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
        child: SafeArea(
          child: Scaffold(
            body: TabBarView(
              children: [
                ChartPage(),
                PortfolioPage(),
              ],
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
      ),
    );
  }
}
