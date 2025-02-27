import 'package:drift/drift.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/utils.dart';
import 'package:share_plus/share_plus.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => PortfolioPageState();
}

class PortfolioPageState extends State<PortfolioPage> {
  late Stream<List<Ticker>> stream;
  final search = TextEditingController();
  List<int> selected = [];

  @override
  void initState() {
    super.initState();
    updateStream();
    Future.delayed(kThemeAnimationDuration).then((_) => updateCandles());
  }

  Future<void> updateCandles() async {
    final tickers = await (db.tickers.select()).get();
    for (final ticker in tickers) {
      await syncCandles(ticker.symbol);
    }
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
        PopupMenuItem(
          child: ListTile(
            title: const Text("Share"),
            leading: const Icon(Icons.share),
            onTap: () async {
              List<Ticker> tickers;
              if (selected.isEmpty)
                tickers = await stream.first;
              else
                tickers = await (db.tickers.select()
                      ..where((u) => u.id.isIn(selected)))
                    .get();
              var csv = "";

              for (final ticker in tickers)
                csv += "${ticker.symbol},${ticker.amount},${ticker.price}\n";

              await Share.share(csv);
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

    var leading = search.text.isEmpty
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
          );
    if (selected.isNotEmpty)
      leading = IconButton(
        onPressed: () {
          setState(() {
            selected.clear();
          });
        },
        icon: const Icon(Icons.arrow_back),
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 8.0,
        ),
      );

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: material.Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: SearchBar(
                controller: search,
                hintText: 'Search...',
                padding: WidgetStateProperty.all(
                  const EdgeInsets.only(right: 8.0),
                ),
                leading: leading,
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
            ),
            StreamBuilder(
              stream: stream,
              builder: streamBuilder,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const EditTickerPage(),
            ),
          );
        },
        label: const Text('Add'),
        icon: const Icon(Icons.add),
        tooltip: 'Add to portfolio',
      ),
    );
  }

  Widget streamBuilder(
    BuildContext context,
    AsyncSnapshot<List<Ticker>> snapshot,
  ) {
    if (!snapshot.hasData) return const SizedBox();
    if (snapshot.data?.isEmpty == true)
      return ListTile(
        title: const Text("No stock found"),
        subtitle: Text("Tap to add ${search.text}"),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => EditTickerPage(
                symbol: search.text.toUpperCase(),
              ),
            ),
          );
        },
      );
    if (snapshot.hasError) return ErrorWidget(snapshot.error.toString());

    final tickers = snapshot.data!;
    final (dollarReturn, percentReturn) = calculateTotalReturns(tickers);
    final total = calculateTotal(tickers);

    return Expanded(
      child: RefreshIndicator(
        onRefresh: updateCandles,
        child: ListView.builder(
          padding: const EdgeInsets.all(0),
          itemBuilder: (context, index) {
            if (index == 0)
              return material.Column(
                children: [
                  const SizedBox(height: 8),
                  Tooltip(
                    message: "Total return of the portfolio",
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance,
                      ),
                      title: Text(currency.format(dollarReturn)),
                      trailing: Text(
                        currency.format(total),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        "${percentReturn.toStringAsFixed(2)}%",
                      ),
                      subtitleTextStyle: TextStyle(
                        color:
                            dollarReturn >= 0 ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  ),
                  const Divider(),
                ],
              );

            final ticker = tickers[index - 1];

            return material.Column(
              children: [
                folioTile(ticker, context),
                if (index == tickers.length) const SizedBox(height: 50),
              ],
            );
          },
          itemCount: tickers.length + 1,
        ),
      ),
    );
  }

  ListTile folioTile(Ticker ticker, BuildContext context) {
    final isSelected = selected.contains(ticker.id);

    return ListTile(
      leading: material.SizedBox(
        height: 30,
        width: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: isSelected ? 0.0 : 1.0,
              child: Visibility(
                visible: !isSelected,
                child: ticker.change >= 0
                    ? const Icon(
                        Icons.arrow_upward,
                        color: Colors.green,
                      )
                    : const Icon(
                        Icons.arrow_downward,
                        color: Colors.red,
                      ),
              ),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: isSelected ? 1.0 : 0.0,
              child: Visibility(
                visible: isSelected,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    if (value == true)
                      setState(() {
                        selected.add(ticker.id);
                      });
                    else
                      setState(() {
                        selected.remove(ticker.id);
                      });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(ticker.symbol),
      subtitle: Text('${ticker.change.toStringAsFixed(2)}%'),
      trailing: Text(
        "${currency.format(ticker.price)} (${ticker.amount})",
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
      subtitleTextStyle: ticker.change >= 0
          ? const TextStyle(color: Colors.green)
          : const TextStyle(color: Colors.red),
      onTap: () {
        if (selected.isEmpty)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditTickerPage(symbol: ticker.symbol),
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
