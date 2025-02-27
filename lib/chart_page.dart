import 'package:drift/drift.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => ChartPageState();
}

class ChartPageState extends State<ChartPage>
    with AutomaticKeepAliveClientMixin {
  TextEditingController stock =
      TextEditingController(text: "GME (GameStop Corporation Common Stock)");
  String? favoriteStock;
  int years = 0;
  int months = 1;
  int days = 0;
  bool loadingChart = false;

  Stream<List<CandleTicker>>? stream;

  final now = DateTime.now();

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
              ),
            ),
            child: Text("${option}m"),
          ),
        ),
      );
    }

    final settings = context.watch<SettingsState>();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                final api = YahooFinanceApi();
                final results = await api.searchTickers(textEditingValue.text);
                return results
                    .map((result) => '${result.symbol} (${result.longname})');
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
                      stock.text = text.toUpperCase();
                      updateData();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
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
          StreamBuilder(
            stream: stream,
            builder: (context, snapshot) =>
                chartBuilder(context, snapshot, settings),
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
    SettingsState settings,
  ) {
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());
    if (snapshot.data == null || snapshot.data?.isEmpty == true || loadingChart)
      return const Center(child: CircularProgressIndicator());

    final candles =
        snapshot.data!.map((tickerCandle) => tickerCandle.candle).toList();
    List<FlSpot> spots = [];
    for (var index = 0; index < candles.length; index++) {
      spots.add(FlSpot(index.toDouble(), candles[index].close.value));
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.3,
      child: TickerLine(
        dates: candles.map((candle) => candle.date.value),
        spots: spots,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  void initData() async {
    final prefs = await SharedPreferences.getInstance();
    stock.text = prefs.getString('favoriteStock') ?? stock.text;

    updateData();
  }

  Future<void> updateData() async {
    if (stock.text.isEmpty) return;
    setStream();
    final symbol = stock.text.split(' ').first;
    await syncCandles(symbol);
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
    setState(() {});
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
                                builder: (context) => EditTickerPage(
                                  symbol: ticker.symbol,
                                ),
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
                onPressed: () async {
                  setState(() {
                    loadingChart = true;
                  });
                  await updateData();
                  setState(() {
                    loadingChart = false;
                  });
                },
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
