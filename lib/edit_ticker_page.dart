import 'package:drift/drift.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';

class EditTickerPage extends StatefulWidget {
  final Ticker ticker;

  const EditTickerPage({super.key, required this.ticker});

  @override
  State<EditTickerPage> createState() => _EditTickerPageState();
}

class _EditTickerPageState extends State<EditTickerPage> {
  Stream<List<CandleTicker>>? stream;

  late final name = TextEditingController(text: widget.ticker.name);
  late final amount =
      TextEditingController(text: widget.ticker.amount.toStringAsFixed(2));
  late final change =
      TextEditingController(text: widget.ticker.change.toStringAsFixed(2));
  late final createdAt = TextEditingController(
    text: widget.ticker.createdAt.toIso8601String(),
  );
  late final price =
      TextEditingController(text: widget.ticker.price.toStringAsFixed(2));
  bool autoSetCreated = false;
  bool autoSetPrice = false;

  @override
  void initState() {
    super.initState();
    setStream();
  }

  void setStream() {
    const weekExpression = CustomExpression<String>(
      "STRFTIME('%Y-%m-%W', DATE(\"date\", 'unixepoch', 'localtime'))",
    );
    Iterable<Expression<Object>> groupBy = [db.candles.date];
    final now = DateTime.now();
    final created = DateTime.parse(createdAt.text);
    if (created.isBefore(DateTime(now.year, now.month - 6, now.day)))
      groupBy = [weekExpression];

    stream = (db.selectOnly(db.candles)
          ..addColumns([
            db.candles.date,
            db.candles.close,
            db.tickers.id,
          ])
          ..where(
            db.candles.symbol.equals(widget.ticker.symbol) &
                db.candles.date.isBiggerOrEqualValue(created),
          )
          ..orderBy(
            [
              OrderingTerm(
                expression: db.candles.date,
                mode: OrderingMode.asc,
              ),
            ],
          )
          ..groupBy(groupBy))
        .join([
          leftOuterJoin(
            db.tickers,
            db.tickers.symbol.equalsExp(db.candles.symbol),
          ),
        ])
        .watch()
        .map(
          (results) => results
              .map(
                (result) => CandleTicker(
                  candle: CandlesCompanion(
                    date: Value(result.read(db.candles.date)!),
                    close: Value(result.read(db.candles.close)!),
                  ),
                  ticker: result.read(db.tickers.id) != null
                      ? TickersCompanion(
                          id: Value(result.read(db.tickers.id)!),
                        )
                      : null,
                ),
              )
              .toList(),
        );
  }

  Widget chartBuilder(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());
    if (snapshot.data == null) return const SizedBox();
    if (snapshot.data!.isEmpty)
      return const ListTile(
        title: Text("No data found"),
        subtitle: Text("Are you sure you typed it correctly?"),
      );

    final candles =
        snapshot.data!.map((tickerCandle) => tickerCandle.candle).toList();
    List<FlSpot> spots = [];
    for (var index = 0; index < candles.length; index++) {
      spots.add(FlSpot(index.toDouble(), candles[index].close.value));
    }

    return TickerLine(
      formatter: DateFormat("d/M/yy"),
      dates: candles.map((candle) => candle.date.value),
      spots: spots,
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
        child: material.Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Stock'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    textInputAction: TextInputAction.next,
                    onTap: () => selectAll(amount),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefix: Text('\$'),
                    ),
                    onTap: () => selectAll(price),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (value) async {
                      if (autoSetPrice) return;
                      final closest = await findClosestPrice(
                        double.parse(price.text),
                        widget.ticker.symbol,
                      );

                      if (closest == null) return;
                      setState(() {
                        createdAt.text = closest.date.toIso8601String();
                        autoSetCreated = true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: createdAt,
                    decoration: const InputDecoration(
                      labelText: 'Created at',
                      suffixIcon: Icon(Icons.today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: widget.ticker.createdAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date == null) return;
                      setState(() {
                        createdAt.text = date.toIso8601String();
                      });
                      setStream();

                      if (autoSetCreated) return;
                      final closest =
                          await findClosestDate(date, widget.ticker.symbol);
                      if (closest == null) return;
                      setState(() {
                        price.text = closest.close.toStringAsFixed(2);
                        autoSetPrice = true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: widget.ticker.change > 0
                        ? const Icon(Icons.arrow_upward, color: Colors.green)
                        : const Icon(Icons.arrow_downward, color: Colors.red),
                    title: Text("${widget.ticker.change.toStringAsFixed(2)}%"),
                    trailing: Text(
                      "Last updated ${widget.ticker.updatedAt}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  StreamBuilder(stream: stream, builder: chartBuilder),
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
              createdAt: Value(DateTime.parse(createdAt.text)),
              price: Value(double.parse(price.text)),
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
