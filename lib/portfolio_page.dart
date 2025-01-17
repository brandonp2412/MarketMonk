import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:market_monk/add_ticker_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  late Stream<List<Ticker>> stream;
  final search = TextEditingController();
  List<int> selected = [];

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
    var deleteButton = IconButton(
      icon: const Icon(Icons.delete),
      tooltip: "Delete selected",
      onPressed: () {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirm Delete'),
              content: Text(
                'Are you sure you want to delete ${selected.length} stocks? This action is not reversible.',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                TextButton(
                  child: const Text('Delete'),
                  onPressed: () async {
                    Navigator.pop(context);
                    await (db.tickers.delete()
                          ..where((u) => u.id.isIn(selected)))
                        .go();
                    setState(() {
                      selected = [];
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );

    var menuButton = PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      tooltip: "Show menu",
      itemBuilder: (context) => [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.done_all),
            title: const Text('Select all'),
            onTap: () async {
              Navigator.pop(context);
              final tickers = await stream.first;
              setState(() {
                selected = tickers.map((ticker) => ticker.id).toList();
              });
            },
          ),
        ),
        if (selected.isNotEmpty)
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear'),
              onTap: () async {
                setState(() {
                  selected = [];
                });
                Navigator.pop(context);
              },
            ),
          ),
        if (selected.isEmpty)
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              },
            ),
          ),
      ],
    );

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
              trailing: [
                if (selected.isNotEmpty) deleteButton,
                Badge.count(
                  count: selected.length,
                  isLabelVisible: selected.isNotEmpty,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: menuButton,
                ),
              ],
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

                      return folioTile(ticker, context);
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

  ListTile folioTile(Ticker ticker, BuildContext context) {
    var leading = ticker.change > 0
        ? const Icon(
            Icons.arrow_upward,
            color: Colors.green,
          )
        : const Icon(
            Icons.arrow_downward,
            color: Colors.red,
          );

    if (selected.contains(ticker.id)) leading = const Icon(Icons.check_circle);

    return ListTile(
      title: Text(ticker.symbol),
      subtitle: Text('${ticker.change.toStringAsFixed(2)}%'),
      selected: selected.contains(ticker.id),
      onLongPress: () {
        if (selected.contains(ticker.id))
          setState(() {
            selected.remove(ticker.id);
          });
        else
          setState(() {
            selected.add(ticker.id);
          });
      },
      subtitleTextStyle: ticker.change > 0
          ? const TextStyle(color: Colors.green)
          : const TextStyle(color: Colors.red),
      leading: leading,
      onTap: () {
        if (selected.isEmpty)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditTickerPage(ticker: ticker),
            ),
          );
        else {
          if (selected.contains(ticker.id))
            setState(() {
              selected.remove(ticker.id);
            });
          else
            setState(() {
              selected.add(ticker.id);
            });
        }
      },
    );
  }
}
