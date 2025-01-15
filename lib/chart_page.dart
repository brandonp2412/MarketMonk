import 'package:drift/drift.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/symbol.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

class CandleTicker {
  final Candle candle;
  final Ticker? ticker;

  CandleTicker({this.ticker, required this.candle});
}

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  TextEditingController stock = TextEditingController(text: "");
  String? favoriteStock;
  List<Symbol> symbols = [];
  int year = 1;
  int month = 0;
  bool loading = false;

  Stream<List<CandleTicker>>? stream;

  final now = DateTime.now();

  @override
  Widget build(BuildContext context) {
    List<Widget> yearButtons = [];
    final yearOptions = [1, 2, 3, 5, 10];
    for (final option in yearOptions) {
      yearButtons.add(
        OutlinedButton(
          onPressed: () {
            setState(() {
              year = option;
              month = 0;
            });
            setStream();
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: option == year
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ), // Set border color
          ),
          child: Text("${option}y"),
        ),
      );
    }

    List<Widget> monthButtons = [];
    final monthOptions = [1, 2, 3, 6];
    for (final option in monthOptions) {
      monthButtons.add(
        OutlinedButton(
          onPressed: () {
            setState(() {
              month = option;
              year = 0;
            });
            setStream();
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: option == month
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ), // Set border color
          ),
          child: Text("${option}m"),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                final filtered = symbols
                    .where(
                      (option) =>
                          option.value
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()) ||
                          option.name
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()),
                    )
                    .toList();
                filtered.sort((a, b) {
                  String text = textEditingValue.text.toLowerCase();
                  bool aStartsWithText = a.value.toLowerCase().startsWith(text);
                  bool bStartsWithText = b.value.toLowerCase().startsWith(text);
                  if (aStartsWithText && !bStartsWithText) return -1;
                  if (!aStartsWithText && bStartsWithText) return 1;
                  return 0;
                });
                return filtered
                    .map((option) => '${option.value} (${option.name})');
              },
              initialValue: stock.value,
              onSelected: (value) => loadData(),
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController fieldTextEditingController,
                FocusNode fieldFocusNode,
                VoidCallback onFieldSubmitted,
              ) {
                stock = fieldTextEditingController;
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
                else if (stock.text.isNotEmpty)
                  leading = IconButton(
                    onPressed: () {
                      setState(() {
                        stock.text = '';
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 8.0,
                    ),
                  );

                return SearchBar(
                  controller: fieldTextEditingController,
                  leading: leading,
                  focusNode: fieldFocusNode,
                  hintText: 'Search...',
                  onTap: () => stock.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: stock.text.length,
                  ),
                  onChanged: (text) {},
                  onSubmitted: (text) {
                    String? selection;

                    for (final option in symbols) {
                      if (option.value.toLowerCase() == text.toLowerCase())
                        selection = '${option.value} (${option.name})';
                    }
                    selection ??= text;
                    stock.text = selection.toUpperCase();
                    loadData();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            children: monthButtons + yearButtons,
          ),
          StreamBuilder(
            stream: stream,
            builder: chartBuilder,
          ),
          StreamBuilder(
            stream: stream,
            builder: summaryBuilder,
          ),
        ],
      ),
    );
  }

  Widget chartBuilder(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());
    if (loading && snapshot.data?.isEmpty == true) return const SizedBox();
    if (snapshot.data == null)
      return const ListTile(title: Text("Pick a stock"));
    if (snapshot.data!.isEmpty)
      return const ListTile(
        title: Text("No data found"),
        subtitle: Text("Are you sure you typed it correctly?"),
      );

    final candles =
        snapshot.data!.map((tickerCandle) => tickerCandle.candle).toList();
    List<FlSpot> spots = [];
    for (var index = 0; index < candles.length; index++) {
      spots.add(FlSpot(index.toDouble(), candles[index].close));
    }

    return TickerLine(
      formatter: DateFormat("d/M/yy"),
      dates: candles.map((candle) => candle.date),
      spots: spots,
    );
  }

  @override
  void initState() {
    super.initState();
    initData();
    getSymbols().then(
      (value) => setState(() {
        symbols = value;
      }),
    );
  }

  void initData() async {
    final prefs = await SharedPreferences.getInstance();
    favoriteStock = prefs.getString('favoriteStock');
    if (favoriteStock != null)
      stock.text = favoriteStock!;
    else {
      final tickers = await (db.tickers.select()
            ..orderBy(
              [
                (u) => OrderingTerm(
                      expression: u.createdAt,
                      mode: OrderingMode.desc,
                    ),
              ],
            )
            ..limit(1))
          .get();
      if (tickers.isNotEmpty)
        stock.text = "${tickers.first.symbol} (${tickers.first.name})";
    }
    refreshData();
  }

  Future<void> insertCandles(
    List<YahooFinanceCandleData> dataList,
    String symbol,
  ) async {
    const int batchSize = 1000;

    for (int i = 0; i < dataList.length; i += batchSize) {
      final batch = dataList.skip(i).take(batchSize).map((data) {
        return CandlesCompanion.insert(
          date: data.date,
          symbol: symbol,
          open: Value(data.open),
          high: Value(data.high),
          low: Value(data.low),
          close: Value(data.close),
          adjClose: Value(data.adjClose),
          volume: Value(data.volume),
        );
      }).toList();

      await db.batch((batchBuilder) {
        batchBuilder.insertAllOnConflictUpdate(
          db.candles,
          batch,
        );
      });

      debugPrint('Inserted ${i + batch.length}');
    }
  }

  void loadData() async {
    setStream();
    setState(() {
      loading = true;
    });
    try {
      final symbol = stock.text.split(' ').first;
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
      );
      await insertCandles(response.candlesData, symbol);
    } finally {
      if (mounted)
        setState(() {
          loading = false;
        });
    }
  }

  void refreshData() async {
    if (stock.text.isEmpty) return;
    setStream();
    setState(() {
      loading = true;
    });

    try {
      final symbol = stock.text.split(' ').first;
      final latest = await (db.candles.select()
            ..where((tbl) => tbl.symbol.equals(symbol))
            ..orderBy(
              [
                (u) => OrderingTerm(
                      expression: u.date,
                      mode: OrderingMode.desc,
                    ),
              ],
            )
            ..limit(1))
          .getSingle();
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
        startDate: latest.date,
      );
      await insertCandles(response.candlesData, symbol);
    } catch (error) {
      if (mounted) toast(context, error.toString());
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  double safePercentChange(double oldValue, double newValue) {
    if (oldValue == 0) return 0;
    return ((newValue - oldValue) / oldValue) * 100;
  }

  void setStream() {
    final now = DateTime.now();
    final after = DateTime(now.year - year, now.month - month, now.day);
    const weekExpression = CustomExpression<String>(
      "STRFTIME('%Y-%m-%W', DATE(\"date\", 'unixepoch', 'localtime'))",
    );
    Iterable<Expression<Object>> groupBy = [db.candles.id];
    if (year > 0 || month > 5) groupBy = [weekExpression];

    stream = (db.selectOnly(db.candles)
          ..addColumns([
            ...db.candles.$columns,
            ...db.tickers.$columns,
          ])
          ..where(
            db.candles.symbol.equals(stock.text.split(' ').first) &
                db.candles.date.isBiggerThanValue(after),
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
                  candle: Candle(
                    id: result.read(db.candles.id)!,
                    symbol: result.read(db.candles.symbol)!,
                    date: result.read(db.candles.date)!,
                    open: result.read(db.candles.open)!,
                    high: result.read(db.candles.high)!,
                    low: result.read(db.candles.low)!,
                    close: result.read(db.candles.close)!,
                    volume: result.read(db.candles.volume)!,
                    adjClose: result.read(db.candles.adjClose)!,
                  ),
                  ticker: result.read(db.tickers.id) != null
                      ? Ticker(
                          id: result.read(db.tickers.id)!,
                          symbol: result.read(db.tickers.symbol)!,
                          name: result.read(db.tickers.name)!,
                          change: result.read(db.tickers.change)!,
                          createdAt: result.read(db.tickers.createdAt)!,
                          updatedAt: result.read(db.tickers.updatedAt)!,
                          amount: result.read(db.tickers.amount)!,
                        )
                      : null,
                ),
              )
              .toList(),
        );
  }

  Widget summaryBuilder(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty)
      return const SizedBox();

    final candles =
        snapshot.data!.map((tickerCandle) => tickerCandle.candle).toList();
    var percentChange =
        safePercentChange(candles.first.close, candles.last.close);
    var color = Colors.green;
    if (percentChange < 0) color = Colors.red;
    var percentStr = percentChange.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: material.Column(
        children: [
          Wrap(
            children: [
              Icon(Icons.arrow_upward, color: color),
              Text(
                "$percentStr%",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge!
                    .copyWith(color: color),
              ),
              const SizedBox(width: 16),
              Text(
                "\$${candles.last.close.toStringAsFixed(2)}",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 8),
            ],
          ),
          Wrap(
            children: [
              if (snapshot.data?.first.ticker != null)
                TextButton.icon(
                  onPressed: () async {
                    final symbol = stock.text.split(' ').first;
                    (db.tickers.delete()..where((u) => u.symbol.equals(symbol)))
                        .go();
                    if (context.mounted)
                      toast(context, 'Removed $symbol from portfolio');
                  },
                  label: const Text("Remove"),
                  icon: const Icon(Icons.remove),
                ),
              if (snapshot.data?.first.ticker == null)
                TextButton.icon(
                  onPressed: () async {
                    final symbol = stock.text.split(' ').first;
                    (db.tickers.insertOne(
                      TickersCompanion.insert(
                        symbol: symbol,
                        amount: 0,
                        change: percentChange,
                        name: stock.text
                            .split(' ')
                            .sublist(1)
                            .join(' ')
                            .replaceAll(RegExp(r'\(|\)'), ''),
                      ),
                    ));
                    if (context.mounted)
                      toast(context, 'Added $symbol to portfolio');
                  },
                  label: const Text("Add"),
                  icon: const Icon(Icons.add),
                ),
              TextButton.icon(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  if (favoriteStock == stock.text) {
                    prefs.remove('favoriteStock');
                    setState(() {
                      favoriteStock = null;
                    });
                    if (context.mounted) toast(context, 'Removed as favorite');
                  } else {
                    prefs.setString('favoriteStock', stock.text);
                    setState(() {
                      favoriteStock = stock.text;
                    });
                    if (context.mounted) toast(context, 'Set as favorite');
                  }
                },
                label: const Text("Favorite"),
                icon: favoriteStock == stock.text
                    ? const Icon(Icons.favorite)
                    : const Icon(Icons.favorite_border),
              ),
              TextButton.icon(
                onPressed: () => refreshData(),
                label: const Text("Refresh"),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
