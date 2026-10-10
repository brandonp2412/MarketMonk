import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:provider/provider.dart';

/// Resolves stock actions using the current favorites and account permissions.
Future<List<DesktopMenuAction>> tickerContextActions(
  BuildContext context,
  String symbol, {
  List<DesktopMenuAction> extraActions = const [],
}) async {
  final settings = await SqliteSettings.getInstance();
  if (!context.mounted) return [];
  final favorite =
      (settings.getStringList('favoriteStocks') ?? []).contains(symbol);
  final managed = context.read<AccountManager>().ibkrConfigFor().enabled;
  return [
    DesktopMenuAction(context.l10n.text('Open chart'), () {
      Navigator.push<void>(
        context,
        adaptivePageRoute(
          context,
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(symbol)),
            body: ChartsPage(initialSymbol: symbol),
          ),
        ),
      );
    }),
    DesktopMenuAction(
        context.l10n.text(favorite ? 'Remove favorite' : 'Add favorite'), () {
      runDetachedTask(
        () async {
          final favorites = [...?settings.getStringList('favoriteStocks')];
          if (favorite) {
            favorites.remove(symbol);
          } else if (!favorites.contains(symbol)) {
            favorites.add(symbol);
          }
          await settings.setStringList('favoriteStocks', favorites);
        }(),
        'Failed to update ticker favorite',
      );
    }),
    if (!managed)
      DesktopMenuAction(context.l10n.text('Add trade'), () {
        Navigator.push<void>(
          context,
          adaptivePageRoute(
            context,
            builder: (_) => EditTickerPage(symbol: symbol),
          ),
        );
      }),
    DesktopMenuAction(context.l10n.text('Copy symbol'), () {
      unawaited(Clipboard.setData(ClipboardData(text: symbol)));
    }),
    ...extraActions,
  ];
}
