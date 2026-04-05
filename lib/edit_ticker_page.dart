import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';

class EditTickerPage extends StatefulWidget {
  final String? symbol;
  final int? tickerId;

  const EditTickerPage({super.key, this.symbol, this.tickerId});

  @override
  State<EditTickerPage> createState() => _EditTickerPageState();
}

class _EditTickerPageState extends State<EditTickerPage> {
  late var symbol = TextEditingController(text: widget.symbol);
  final amount = TextEditingController(text: '1');
  final purchasedAt = TextEditingController();
  DateTime _purchasedDate = DateTime.now();
  final price = TextEditingController(text: '0');

  Stream<List<CandleTicker>>? stream;
  bool autoSetCreated = false;
  bool autoSetPrice = false;
  bool loading = false;
  bool _isSell = false;
  int years = 0;
  int months = 0;
  int days = 5;

  FocusNode? autocomplete;

  static final _dateDisplay = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    purchasedAt.text = _dateDisplay.format(_purchasedDate);
    setStream();
    setTicker();
  }

  void setTicker() async {
    final tickerId = widget.tickerId;
    if (tickerId == null) return;

    final ticker = await (db.tickers.select()
          ..where((tbl) => tbl.id.equals(tickerId)))
        .getSingleOrNull();
    if (ticker == null) return;

    symbol.text = ticker.symbol;
    price.text = ticker.price.toStringAsFixed(2);
    amount.text = ticker.amount.toStringAsFixed(2);
    _purchasedDate = ticker.purchasedAt;
    purchasedAt.text = _dateDisplay.format(_purchasedDate);
    setState(() {});
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
    if (snapshot.data!.isEmpty && !loading)
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

    var percentChange = safePercentChange(
      candles.first.close.value,
      candles.lastOrNull?.close.value ?? 0,
    );

    return material.Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: TickerLine(
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
                      optionsBuilder:
                          (TextEditingValue textEditingValue) async {
                        final api = YahooFinanceApi();
                        final results =
                            await api.searchTickers(textEditingValue.text);
                        return results.map(
                          (result) => '${result.symbol} (${result.longname})',
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
                          trailing: getTrailing,
                          controller: fieldTextEditingController,
                          leading: leading,
                          focusNode: fieldFocusNode,
                          hintText: 'Search...',
                          onTap: () => selectAll(symbol),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (text) async {
                            selectAll(amount);
                            symbol.text = text.toUpperCase();
                            setStream();

                            setState(() {
                              loading = true;
                            });
                            try {
                              await syncCandles(text.split(' ').first);
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
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Buy'),
                        icon: Icon(Icons.arrow_downward),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Sell'),
                        icon: Icon(Icons.arrow_upward),
                      ),
                    ],
                    selected: {_isSell},
                    onSelectionChanged: (v) =>
                        setState(() => _isSell = v.first),
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
                        _purchasedDate = closest.date;
                        purchasedAt.text = _dateDisplay.format(closest.date);
                        autoSetCreated = true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: purchasedAt,
                    decoration: const InputDecoration(
                      labelText: 'Purchased at',
                      suffixIcon: Icon(Icons.today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: _purchasedDate,
                        firstDate: DateTime(0),
                        lastDate: DateTime.now(),
                      );
                      if (date == null) return;
                      setState(() {
                        _purchasedDate = date;
                        purchasedAt.text = _dateDisplay.format(date);
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
                        _purchasedDate = closest.date;
                        purchasedAt.text = _dateDisplay.format(closest.date);
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

          final percentChange = safePercentChange(
            double.parse(price.text),
            candleTickers.lastOrNull?.candle.close.value ?? 0,
          );

          final name = symbol.text
              .split(' ')
              .sublist(1)
              .join(' ')
              .replaceAll(RegExp(r'\(|\)'), '');

          final tickerSymbol = symbol.text.split(' ').first;
          final qty = double.parse(amount.text);

          // Always record a trade entry
          await db.trades.insertOne(
            TradesCompanion.insert(
              symbol: tickerSymbol,
              name: name.isNotEmpty ? name : tickerSymbol,
              quantity: _isSell ? -qty : qty,
              price: double.parse(price.text),
              tradeType: _isSell ? 'close' : 'open',
              tradeDate: _purchasedDate,
            ),
          );

          final tickerId = widget.tickerId;
          if (tickerId != null) {
            (db.tickers.update()..where((tbl) => tbl.id.equals(tickerId)))
                .write(
              TickersCompanion(
                amount: Value(double.parse(amount.text)),
                updatedAt: Value(DateTime.now()),
                purchasedAt: Value(_purchasedDate),
                price: Value(double.parse(price.text)),
                name: Value(name),
                symbol: Value(tickerSymbol),
                change: Value(percentChange),
              ),
            );
          } else if (!_isSell) {
            db.tickers.insertOne(
              TickersCompanion(
                amount: Value(double.parse(amount.text)),
                updatedAt: Value(DateTime.now()),
                purchasedAt: Value(_purchasedDate),
                price: Value(double.parse(price.text)),
                name: Value(name),
                symbol: Value(tickerSymbol),
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

  List<material.Widget> get getTrailing {
    return [
      StreamBuilder(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.data == null) return const SizedBox();

          final percentChange = safePercentChange(
            double.parse(price.text),
            snapshot.data?.lastOrNull?.candle.close.value ?? 0,
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
    ];
  }
}
