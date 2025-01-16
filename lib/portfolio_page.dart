import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:market_monk/add_ticker_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  late Stream<List<Ticker>> stream;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    updateStream();
  }

  void updateStream() {
    setState(() {
      stream = (db.tickers.select()
            ..where(
              (tbl) => tbl.symbol.contains(search.text.toLowerCase()),
            )
            ..orderBy(
              [
                (u) => OrderingTerm(
                      expression: u.createdAt,
                      mode: OrderingMode.desc,
                    ),
              ],
            ))
          .watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: material.Column(
          children: [
            if (Platform.isAndroid) const SizedBox(height: 40),
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
                if (snapshot.data?.isEmpty == true)
                  return const ListTile(
                    title: Text("No portfolio yet"),
                    subtitle: Text("Swipe over to Charts to add some tickers!"),
                  );
                if (snapshot.hasError)
                  return ErrorWidget(snapshot.error.toString());

                final tickers = snapshot.data!;

                return Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(0),
                    itemBuilder: (context, index) {
                      final ticker = tickers[index];

                      return ListTile(
                        title: Text(ticker.symbol),
                        subtitle: Text('${ticker.change.toStringAsFixed(2)}%'),
                        subtitleTextStyle: ticker.change > 0
                            ? const TextStyle(color: Colors.green)
                            : const TextStyle(color: Colors.red),
                        leading: ticker.change > 0
                            ? const Icon(
                                Icons.arrow_upward,
                                color: Colors.green,
                              )
                            : const Icon(
                                Icons.arrow_downward,
                                color: Colors.red,
                              ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditTickerPage(ticker: ticker),
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddTickerPage(),
            ),
          );
        },
        label: const Text('Add'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
