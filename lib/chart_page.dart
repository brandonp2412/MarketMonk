import 'package:drift/drift.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  final symbol = TextEditingController(text: "GOOG");
  int year = 1;
  int month = 0;

  late Stream<List<Ticker>> tickerStream = (db.tickers.select()
        ..where(
          (tbl) => tbl.symbol.equals(symbol.text),
        )
        ..limit(1))
      .watch();

  final now = DateTime.now();
  late var future = const YahooFinanceDailyReader().getDailyDTOs(
    "GOOG",
    startDate: DateTime(now.year - 1, now.month, now.day),
  );

  void loadData() {
    setState(() {
      future = const YahooFinanceDailyReader().getDailyDTOs(
        symbol.text,
        startDate: DateTime(now.year - year, now.month - month, now.day),
      );
      tickerStream = (db.tickers.select()
            ..where(
              (tbl) => tbl.symbol.equals(symbol.text),
            )
            ..limit(1))
          .watch();
    });
  }

  double safePercentChange(double oldValue, double newValue) {
    if (oldValue == 0) return 0;
    return ((newValue - oldValue) / oldValue) * 100;
  }

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
            loadData();
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
            loadData();
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
            child: TextField(
              decoration: const InputDecoration(labelText: 'Ticker'),
              controller: symbol,
              onSubmitted: (value) => loadData(),
              onTap: () => symbol.selection = TextSelection(
                baseOffset: 0,
                extentOffset: symbol.text.length,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            children: monthButtons + yearButtons,
          ),
          FutureBuilder(
            future: future,
            builder: chartBuilder,
          ),
          FutureBuilder(
            future: future,
            builder: summaryBuilder,
          ),
          const SizedBox(height: 16),
          Wrap(
            children: [
              StreamBuilder(stream: tickerStream, builder: buttonsBuilder),
            ],
          ),
        ],
      ),
    );
  }

  Widget buttonsBuilder(
    BuildContext context,
    AsyncSnapshot<List<Ticker>> snapshot,
  ) {
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());

    if (snapshot.data?.isNotEmpty == true)
      return TextButton.icon(
        onPressed: () async {
          await (db.tickers.delete()
                ..where((u) => u.symbol.equals(symbol.text)))
              .go();
        },
        label: const Text("Remove from portfolio"),
        icon: const Icon(Icons.remove),
      );

    return TextButton.icon(
      onPressed: () async {
        final data = (await future).candlesData;
        final percentChange =
            safePercentChange(data.first.close, data.last.close);
        await (db.tickers.insertOne(
          TickersCompanion.insert(
            symbol: symbol.text,
            amount: 0,
            change: percentChange,
          ),
        ));
      },
      label: const Text("Add to portfolio"),
      icon: const Icon(Icons.add),
    );
  }

  Widget chartBuilder(
    BuildContext context,
    AsyncSnapshot<YahooFinanceResponse> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(
        child: SizedBox(
          height: 50,
          width: 50,
          child: CircularProgressIndicator(),
        ),
      );

    final candles = snapshot.data!.candlesData;
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

  Widget summaryBuilder(context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const SizedBox();
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());
    if (!snapshot.hasData || snapshot.data == null)
      return ErrorWidget("No data.");

    final candles = snapshot.data!.candlesData;
    var percentChange =
        safePercentChange(candles.first.close, candles.last.close);
    var color = Colors.green;
    if (percentChange < 0) color = Colors.red;
    var percentStr = percentChange.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(Icons.arrow_upward, color: color),
          Text(
            "$percentStr%",
            style:
                Theme.of(context).textTheme.titleLarge!.copyWith(color: color),
          ),
          const SizedBox(width: 16),
          Text(
            "\$${candles.last.close.toStringAsFixed(2)}",
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}
