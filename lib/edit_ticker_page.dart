import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/symbol.dart';
import 'package:market_monk/utils.dart';

class EditTickerPage extends StatefulWidget {
  final Ticker ticker;

  const EditTickerPage({super.key, required this.ticker});

  @override
  State<EditTickerPage> createState() => _EditTickerPageState();
}

class _EditTickerPageState extends State<EditTickerPage> {
  final stock = TextEditingController();
  late final amount =
      TextEditingController(text: widget.ticker.amount.toStringAsFixed(2));
  late final change =
      TextEditingController(text: widget.ticker.change.toStringAsFixed(2));
  late final createdAt = TextEditingController(
    text: widget.ticker.createdAt.toIso8601String(),
  );
  late final updatedAt = TextEditingController(
    text: widget.ticker.updatedAt.toIso8601String(),
  );

  @override
  void initState() {
    super.initState();

    getSymbols().then(
      (symbols) => setState(() {
        stock.text = symbols
            .firstWhere((symbol) => symbol.value == widget.ticker.symbol)
            .name;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticker.symbol),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: stock,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Stock'),
            ),
            TextField(
              controller: amount,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            TextField(
              controller: change,
              decoration: const InputDecoration(labelText: 'Change %'),
            ),
            TextField(
              controller: createdAt,
              decoration: const InputDecoration(labelText: 'Created at'),
              readOnly: true,
            ),
            TextField(
              controller: updatedAt,
              decoration: const InputDecoration(labelText: 'Updated at'),
              readOnly: true,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          (db.tickers.update()..where((tbl) => tbl.id.equals(widget.ticker.id)))
              .write(
            TickersCompanion(
              amount: Value(double.parse(amount.text)),
              change: Value(double.parse(change.text)),
              updatedAt: Value(DateTime.now()),
            ),
          );
          Navigator.of(context).pop();
        },
        label: const Text('Save'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
