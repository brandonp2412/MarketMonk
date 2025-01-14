import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  late Stream<List<Ticker>> stream = (db.tickers.select()).watch();
  final search = TextEditingController();

  void updateStream() {
    setState(() {
      stream = (db.tickers.select()
            ..where(
              (tbl) => tbl.symbol.contains(search.text.toLowerCase()),
            ))
          .watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: material.Column(
        children: [
          SearchBar(
            controller: search,
            hintText: 'Search...',
            leading: search.text.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(left: 16.0, right: 8.0),
                    child: Icon(Icons.search),
                  )
                : IconButton(
                    onPressed: () {
                      search.text = '';
                      updateStream();
                    },
                    icon: const Icon(Icons.arrow_back),
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 8.0,
                    ),
                  ),
            onTap: () => search.selection = TextSelection(
              baseOffset: 0,
              extentOffset: search.text.length,
            ),
            onChanged: (text) {
              updateStream();
            },
          ),
          StreamBuilder(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              if (snapshot.hasError)
                return ErrorWidget(snapshot.error.toString());

              final tickers = snapshot.data!;

              return Expanded(
                child: ListView.builder(
                  itemBuilder: (context, index) {
                    final ticker = tickers[index];

                    return ListTile(
                      title: Text(ticker.symbol),
                      subtitle: Text('${ticker.change.toStringAsFixed(2)}%'),
                      subtitleTextStyle: ticker.change > 0
                          ? const TextStyle(color: Colors.green)
                          : const TextStyle(color: Colors.red),
                      leading: ticker.change > 0
                          ? const Icon(Icons.arrow_upward, color: Colors.green)
                          : const Icon(Icons.arrow_downward, color: Colors.red),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditTickerPage(ticker: ticker),
                        ),
                      ),
                    );
                  },
                  itemCount: tickers.length,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
