import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  final ticker = TextEditingController(text: "GOOG");
  final now = DateTime.now();
  late var future = const YahooFinanceDailyReader().getDailyDTOs(
    "GOOG",
    startDate: DateTime(now.year - 1, now.month, now.day),
  );
  int year = 1;
  int month = 0;
  double change = 0.0;

  void loadMonth(int value) {
    setState(() {
      month = value;
      year = 0;
      future = const YahooFinanceDailyReader().getDailyDTOs(
        ticker.text,
        startDate: DateTime(now.year, now.month - value, now.day),
      );
    });
  }

  void loadYear(int value) {
    setState(() {
      year = value;
      month = 0;
      future = const YahooFinanceDailyReader().getDailyDTOs(
        ticker.text,
        startDate: DateTime(now.year - value, now.month, now.day),
      );
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
          onPressed: () => loadYear(option),
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
          onPressed: () => loadMonth(option),
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
              controller: ticker,
              onSubmitted: (value) => loadYear(year),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            children: monthButtons + yearButtons,
          ),
          FutureBuilder(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const SizedBox();
              if (snapshot.hasError)
                return ErrorWidget(snapshot.error.toString());
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
                  ],
                ),
              );
            },
          ),
          FutureBuilder(
            future: future,
            builder: (context, snapshot) {
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
            },
          ),
        ],
      ),
    );
  }
}
