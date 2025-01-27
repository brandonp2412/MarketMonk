import 'package:drift/drift.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:intl/intl.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/symbol.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage>
    with AutomaticKeepAliveClientMixin {
  TextEditingController stock = TextEditingController(text: "GME");
  String? favoriteStock;
  List<Symbol> symbols = [];
  int years = 0;
  int months = 0;
  int days = 5;
  bool loading = false;

  Stream<List<CandleTicker>>? stream;

  final now = DateTime.now();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Widget> yearButtons = [];
    final yearOptions = [1, 2, 3, 5, 10];
    for (final option in yearOptions) {
      yearButtons.add(
        OutlinedButton(
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
      );
    }

    List<Widget> monthButtons = [];
    final monthOptions = [1, 2, 3, 6];
    for (final option in monthOptions) {
      monthButtons.add(
        OutlinedButton(
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
              onSelected: (value) => updateData(),
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

                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SearchBar(
                    controller: fieldTextEditingController,
                    leading: leading,
                    focusNode: fieldFocusNode,
                    hintText: 'Search...',
                    onTap: () => stock.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: stock.text.length,
                    ),
                    trailing: [
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings),
                      ),
                    ],
                    onSubmitted: (text) {
                      String? selection;

                      for (final option in symbols) {
                        if (option.value.toLowerCase() == text.toLowerCase())
                          selection = '${option.value} (${option.name})';
                      }
                      selection ??= text;
                      stock.text = selection.toUpperCase();
                      updateData();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            children: [
              OutlinedButton(
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
              ...monthButtons,
              ...yearButtons,
            ],
          ),
          StreamBuilder(
            stream: stream,
            builder: chartBuilder,
          ),
          const SizedBox(height: 8),
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
  void initState() {
    super.initState();
    initData();
  }

  void initData() async {
    final gotSymbols = await getSymbols();
    setState(() {
      symbols = gotSymbols;
    });

    final prefs = await SharedPreferences.getInstance();
    stock.text = prefs.getString('favoriteStock') ?? "";
    if (stock.text.isEmpty) {
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

    updateData();
  }

  void updateData() async {
    if (stock.text.isEmpty) return;
    setStream();
    setState(() {
      loading = true;
    });

    try {
      final symbol = stock.text.split(' ').first;
      await syncCandles(symbol);
    } catch (error) {
      if (mounted) toast(context, error.toString());
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  void setStream() {
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

  Widget summaryBuilder(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty)
      return const SizedBox();

    final candles =
        snapshot.data!.map((tickerCandle) => tickerCandle.candle).toList();
    var percentChange =
        safePercentChange(candles.first.close.value, candles.last.close.value);
    var color = Colors.green;
    if (percentChange < 0) color = Colors.red;
    var percentStr = percentChange.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: material.Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                "\$${candles.last.close.value.toStringAsFixed(2)}",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                    final ticker = await (db.tickers.insertReturning(
                      TickersCompanion.insert(
                        symbol: symbol,
                        amount: 1,
                        change: percentChange,
                        price: candles.last.close.value,
                        name: stock.text
                            .split(' ')
                            .sublist(1)
                            .join(' ')
                            .replaceAll(RegExp(r'\(|\)'), ''),
                        createdAt: Value(
                          DateTime.now().subtract(const Duration(days: 30)),
                        ),
                      ),
                    ));
                    if (context.mounted)
                      toast(
                        context,
                        'Added $symbol to portfolio',
                        SnackBarAction(
                          label: 'Edit',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    EditTickerPage(ticker: ticker),
                              ),
                            );
                          },
                        ),
                      );
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
                onPressed: () => updateData(),
                label: const Text("Refresh"),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
