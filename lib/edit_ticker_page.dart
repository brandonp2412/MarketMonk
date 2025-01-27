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

class EditTickerPage extends StatefulWidget {
  final String? symbol;

  const EditTickerPage({super.key, this.symbol});

  @override
  State<EditTickerPage> createState() => _EditTickerPageState();
}

class _EditTickerPageState extends State<EditTickerPage> {
  late var symbol = TextEditingController(text: widget.symbol);
  final amount = TextEditingController(text: '1');
  final createdAt = TextEditingController(
    text: DateTime.now().toIso8601String(),
  );
  final price = TextEditingController(text: '0');

  Stream<List<CandleTicker>>? stream;
  bool autoSetCreated = false;
  bool autoSetPrice = false;
  bool loading = false;
  List<Symbol> symbols = [];
  int years = 0;
  int months = 0;
  int days = 5;

  FocusNode? autocomplete;

  @override
  void initState() {
    super.initState();
    setStream();
    setSymbols();
    setTicker();
  }

  void setTicker() async {
    if (widget.symbol == null) return;

    final ticker = await (db.tickers.select()
          ..where((tbl) => tbl.symbol.equals(widget.symbol!.split(' ').first)))
        .getSingleOrNull();
    if (ticker == null) return;

    price.text = ticker.price.toStringAsFixed(2);
    amount.text = ticker.amount.toStringAsFixed(2);
    createdAt.text = ticker.createdAt.toIso8601String();
  }

  void setSymbols() async {
    final gotSymbols = await getSymbols();
    setState(() {
      symbols = gotSymbols;
    });
    if (widget.symbol == null) autocomplete?.requestFocus();
  }

  void setStream() {
    if (symbol.text.isEmpty) return;

    final now = DateTime.now();
    final after =
        DateTime(now.year - years, now.month - months, now.day - days - 1);
    const weekExpression = CustomExpression<String>(
      "STRFTIME('%Y-%m-%W', DATE(\"date\", 'unixepoch', 'localtime'))",
    );
    Iterable<Expression<Object>> groupBy = [db.candles.date];
    if (years > 0 || months > 5) groupBy = [weekExpression];

    stream = (db.selectOnly(db.candles)
          ..addColumns([
            db.candles.date,
            db.candles.close,
            db.tickers.id,
            db.tickers.price,
          ])
          ..where(
            db.candles.symbol.equals(symbol.text.split(' ').first) &
                db.candles.date.isBiggerOrEqualValue(after),
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
                          price: Value(result.read(db.tickers.price)!),
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
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: TickerLine(
            formatter: DateFormat("d/M/yy"),
            dates: candles.map((candle) => candle.date.value),
            spots: spots,
          ),
        ),
        ListTile(
          leading: percentChange > 0
              ? const Icon(Icons.arrow_upward, color: Colors.green)
              : const Icon(Icons.arrow_downward, color: Colors.red),
          title: Text("${percentChange.toStringAsFixed(2)}%"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> yearButtons = [];
    final yearOptions = [1, 2, 3, 5, 10];
    for (final option in yearOptions) {
      yearButtons.add(
        Tooltip(
          message: 'Show the $option last years of prices',
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                years = option;
                months = 0;
                days = 0;
              });
              setStream();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: option == years
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ), // Set border color
            ),
            child: Text("${option}y"),
          ),
        ),
      );
    }

    List<Widget> monthButtons = [];
    final monthOptions = [1, 2, 3, 6];
    for (final option in monthOptions) {
      monthButtons.add(
        Tooltip(
          message: "Show the last $option months of prices",
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                months = option;
                years = 0;
                days = 0;
              });
              setStream();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: option == months
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ), // Set border color
            ),
            child: Text("${option}m"),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit investment"),
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

                        final results = await stream?.first;
                        if (results == null) return;
                        price.text =
                            results.last.candle.close.value.toStringAsFixed(2);
                      },
                      fieldViewBuilder: (
                        BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted,
                      ) {
                        symbol = fieldTextEditingController;
                        autocomplete = fieldFocusNode;
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
                          trailing: [
                            StreamBuilder(
                              stream: stream,
                              builder: (context, snapshot) {
                                if (snapshot.data == null)
                                  return const SizedBox();

                                final percentChange = safePercentChange(
                                  double.parse(price.text),
                                  snapshot.data!.last.candle.close.value,
                                );

                                return material.Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Row(
                                    children: [
                                      percentChange >= 0
                                          ? const Icon(
                                              Icons.arrow_upward,
                                              color: Colors.green,
                                            )
                                          : const Icon(
                                              Icons.arrow_downward,
                                              color: Colors.red,
                                            ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${percentChange.toStringAsFixed(2)}%",
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          controller: fieldTextEditingController,
                          leading: leading,
                          focusNode: fieldFocusNode,
                          hintText: 'Search...',
                          onTap: () => selectAll(symbol),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (text) async {
                            selectAll(amount);
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
                    onSubmitted: (value) => selectAll(price),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefix: Text("\$"),
                    ),
                    onTap: () => selectAll(price),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
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
                      labelText: 'Purchased at',
                      suffixIcon: Icon(Icons.today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.parse(createdAt.text),
                        firstDate: DateTime(0),
                        lastDate: DateTime.now(),
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
                  const SizedBox(height: 16),
                  Wrap(
                    children: [
                      Tooltip(
                        message: 'Show the last 5 days of prices',
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              days = 5;
                              years = 0;
                              months = 0;
                            });
                            setStream();
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: days == 5
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ), // Set border color
                          ),
                          child: const Text("5d"),
                        ),
                      ),
                      ...monthButtons,
                      ...yearButtons,
                    ],
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
        onPressed: () async {
          Navigator.of(context).pop();

          final candleTickers = await stream?.first;
          if (candleTickers == null) return;

          var percentChange = safePercentChange(
            candleTickers.first.candle.close.value,
            candleTickers.last.candle.close.value,
          );

          final name = symbol.text
              .split(' ')
              .sublist(1)
              .join(' ')
              .replaceAll(RegExp(r'\(|\)'), '');

          final exists = await (db.tickers.select()
                ..where(
                  (tbl) => tbl.symbol.equals(symbol.text.split(' ').first),
                ))
              .getSingleOrNull();

          if (exists != null) {
            (db.tickers.update()..where((tbl) => tbl.id.equals(exists.id)))
                .write(
              TickersCompanion(
                amount: Value(double.parse(amount.text)),
                updatedAt: Value(DateTime.now()),
                createdAt: Value(DateTime.parse(createdAt.text)),
                price: Value(double.parse(price.text)),
                name: Value(name),
                symbol: Value(symbol.text.split(' ').first),
                change: Value(percentChange),
              ),
            );
          } else {
            db.tickers.insertOne(
              TickersCompanion(
                amount: Value(double.parse(amount.text)),
                updatedAt: Value(DateTime.now()),
                createdAt: Value(DateTime.parse(createdAt.text)),
                price: Value(double.parse(price.text)),
                name: Value(name),
                symbol: Value(symbol.text.split(' ').first),
                change: Value(percentChange),
              ),
            );
          }
        },
        label: const Text('Save'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
