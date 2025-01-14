import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  late Stream<List<Ticker>> stream = (db.tickers.select()).watch();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: StreamBuilder(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());

          final tickers = snapshot.data!;

          return ListView.builder(
            itemBuilder: (context, index) {
              final ticker = tickers[index];

              return ListTile(
                title: Text(ticker.symbol),
                subtitle: Text('${ticker.change.toStringAsFixed(2)}%'),
                subtitleTextStyle: ticker.change > 0
                    ? const TextStyle(color: Colors.green)
                    : const TextStyle(color: Colors.red),
                leading: ticker.change > 0
                    ? const Icon(Icons.arrow_upward, color: Colors.green)
                    : const Icon(Icons.arrow_downward, color: Colors.red),
              );
            },
            itemCount: tickers.length,
          );
        },
      ),
    );
  }
}
