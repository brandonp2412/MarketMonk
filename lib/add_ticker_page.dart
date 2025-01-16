import 'package:drift/drift.dart';
import 'package:market_monk/symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';

class AddTickerPage extends StatefulWidget {
  const AddTickerPage({super.key});

  @override
  State<AddTickerPage> createState() => _AddTickerPageState();
}

class _AddTickerPageState extends State<AddTickerPage> {
  var symbol = TextEditingController();
  final amount = TextEditingController(text: '0');
  final createdAt = TextEditingController(
    text: DateTime.now().subtract(const Duration(days: 100)).toIso8601String(),
  );
  final price = TextEditingController(text: '0');

  Stream<List<CandleTicker>>? stream;
  bool autoSetCreated = false;
  bool autoSetPrice = false;
  bool loading = false;
  List<Symbol> symbols = [];

  @override
  void initState() {
    super.initState();
    setStream();
    setSymbols();
  }

  void setSymbols() async {
    final gotSymbols = await getSymbols();
    setState(() {
      symbols = gotSymbols;
    });
  }

  void setStream() {
    if (symbol.text.isEmpty) return;

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
            db.candles.symbol.equals(symbol.text.split(' ').first) &
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
    setState(() {});
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

    var percentChange =
        safePercentChange(candles.first.close.value, candles.last.close.value);

    return material.Column(
      children: [
        ListTile(
          leading: percentChange > 0
              ? const Icon(Icons.arrow_upward, color: Colors.green)
              : const Icon(Icons.arrow_downward, color: Colors.red),
          title: Text("${percentChange.toStringAsFixed(2)}%"),
          trailing: Text(
            "Last updated ${candles.last.date.value}",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        TickerLine(
          formatter: DateFormat("d/M/yy"),
          dates: candles.map((candle) => candle.date.value),
          spots: spots,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add to portfolio"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: material.Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final filtered = symbols
                            .where(
                              (option) =>
                                  option.value.toLowerCase().contains(
                                        textEditingValue.text.toLowerCase(),
                                      ) ||
                                  option.name.toLowerCase().contains(
                                        textEditingValue.text.toLowerCase(),
                                      ),
                            )
                            .toList();
                        filtered.sort((a, b) {
                          String text = textEditingValue.text.toLowerCase();
                          bool aStartsWithText =
                              a.value.toLowerCase().startsWith(text);
                          bool bStartsWithText =
                              b.value.toLowerCase().startsWith(text);
                          if (aStartsWithText && !bStartsWithText) return -1;
                          if (!aStartsWithText && bStartsWithText) return 1;
                          return 0;
                        });
                        return filtered.map(
                          (option) => '${option.value} (${option.name})',
                        );
                      },
                      initialValue: symbol.value,
                      onSelected: (value) async {
                        setStream();
                        setState(() {
                          loading = true;
                        });
                        try {
                          await syncCandles(value.split(' ').first);
                        } catch (error) {
                          if (context.mounted) toast(context, error.toString());
                        } finally {
                          setState(() {
                            loading = false;
                          });
                        }
                      },
                      fieldViewBuilder: (
                        BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted,
                      ) {
                        symbol = fieldTextEditingController;
                        Widget leading = const Padding(
                          padding: EdgeInsets.only(left: 16.0, right: 8.0),
                          child: Icon(Icons.search),
                        );
                        if (loading)
                          leading = const Padding(
                            padding: EdgeInsets.only(left: 16.0, right: 8.0),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(),
                            ),
                          );

                        return SearchBar(
                          controller: fieldTextEditingController,
                          leading: leading,
                          focusNode: fieldFocusNode,
                          hintText: 'Search...',
                          onTap: () => selectAll(symbol),
                          onSubmitted: (text) async {
                            String? selection;

                            for (final option in symbols) {
                              if (option.value.toLowerCase() ==
                                  text.toLowerCase())
                                selection = '${option.value} (${option.name})';
                            }
                            selection ??= text;
                            symbol.text = selection.toUpperCase();
                            setStream();

                            setState(() {
                              loading = true;
                            });
                            try {
                              await syncCandles(selection.split(' ').first);
                            } catch (error) {
                              if (context.mounted)
                                toast(context, error.toString());
                              debugPrint(error.toString());
                            } finally {
                              setState(() {
                                loading = false;
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    onTap: () => selectAll(amount),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price,
                    decoration: const InputDecoration(labelText: 'Price \$'),
                    onTap: () => selectAll(price),
                    keyboardType: TextInputType.number,
                    onSubmitted: (value) async {
                      if (autoSetPrice) return;
                      final closest = await findClosestPrice(
                        double.parse(price.text),
                        symbol.text.split(' ').first,
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
                        initialDate: DateTime.parse(createdAt.text),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date == null) return;
                      setState(() {
                        createdAt.text = date.toIso8601String();
                      });
                      setStream();

                      if (autoSetCreated) return;
                      final closest = await findClosestDate(
                        date,
                        symbol.text.split(' ').first,
                      );
                      if (closest == null) return;
                      setState(() {
                        price.text = closest.close.toStringAsFixed(2);
                        autoSetPrice = true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder(stream: stream, builder: chartBuilder),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          db.tickers.insertOne(
            TickersCompanion(
              amount: Value(double.parse(amount.text)),
              updatedAt: Value(DateTime.now()),
              createdAt: Value(DateTime.parse(createdAt.text)),
              price: Value(double.parse(price.text)),
              name: Value(symbol.text.split(' ').sublist(1).join(' ')),
              symbol: Value(symbol.text.split(' ').first),
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
