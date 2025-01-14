import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';

class EditTickerPage extends StatefulWidget {
  final Ticker ticker;

  const EditTickerPage({super.key, required this.ticker});

  @override
  State<EditTickerPage> createState() => _EditTickerPageState();
}

class _EditTickerPageState extends State<EditTickerPage> {
  late final name = TextEditingController(text: widget.ticker.name);
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticker.symbol),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: material.Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Stock'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: change,
                    decoration: const InputDecoration(labelText: 'Change %'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: createdAt,
                    decoration: const InputDecoration(labelText: 'Created at'),
                    readOnly: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: updatedAt,
                    decoration: const InputDecoration(labelText: 'Updated at'),
                    readOnly: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        label: const Text('Delete'),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Are you sure?"),
                              content: const Text("Deleting is irreversible."),
                              actions: [
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(true);
                                  },
                                  icon: const Icon(Icons.delete),
                                  label: const Text("OK"),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(false);
                                  },
                                  icon: const Icon(Icons.close),
                                  label: const Text("Cancel"),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;

                          db.tickers.deleteOne(
                            TickersCompanion(id: Value(widget.ticker.id)),
                          );
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete),
                      ),
                    ],
                  ),
                ],
              ),
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
              name: Value(name.text),
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
