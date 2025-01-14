import 'package:flutter/material.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/portfolio_page.dart';

void main() {
  runApp(const MyApp());
}

Database db = Database();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketMonk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset('assets/meditation.png'),
          ),
          title: const Text("MarketMonk"),
        ),
        body: const TabBarView(
          children: [
            ChartPage(),
            PortfolioPage(),
          ],
        ),
        bottomNavigationBar: const TabBar(
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
    );
  }
}
