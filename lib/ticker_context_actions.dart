import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/app.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/google_finance_url.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

Future<void> _openGoogleFinance(String symbol) async {
  var url = googleFinanceUrl(symbol);
  if (url.contains('/finance/search?')) {
    final yahoo = YahooFinanceApi();
    try {
      final matches = await yahoo.searchTickers(symbol);
      for (final match in matches) {
        if (match.symbol.toUpperCase() != symbol.toUpperCase()) continue;
        url = googleFinanceUrl(symbol, yahooExchange: match.exchange);
        break;
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Google Finance exchange lookup failed');
    } finally {
      yahoo.dispose();
    }
  }
  await launchUrlString(url);
}

/// Resolves stock actions using the current favorites and account permissions.
Future<List<DesktopMenuAction>> tickerContextActions(
  BuildContext context,
  String symbol, {
  List<DesktopMenuAction> extraActions = const [],
}) async {
  final settings = await SqliteSettings.getInstance();
  if (!context.mounted) return [];
  final favorite = (settings.getStringList('favoriteStocks') ?? []).contains(
    symbol,
  );
  final managed = context.read<AccountManager>().ibkrConfigFor().enabled;
  final encoded = Uri.encodeComponent(symbol);
  return [
    DesktopMenuAction(
      context.l10n.text('Open chart'),
      () {
        if (isDesktopLayout(context)) {
          ChartsFocusController.instance.focus(symbol);
          return;
        }
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
      },
      icon: Icons.show_chart_rounded,
    ),
    DesktopMenuAction(
      context.l10n.text(favorite ? 'Remove favorite' : 'Add favorite'),
      () {
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
      },
      icon: favorite ? Icons.star_rounded : Icons.star_border_rounded,
    ),
    if (!managed)
      DesktopMenuAction(
        context.l10n.text('Add trade'),
        () {
          Navigator.push<void>(
            context,
            adaptivePageRoute(
              context,
              builder: (_) => EditTickerPage(symbol: symbol),
            ),
          );
        },
        icon: Icons.add_rounded,
      ),
    DesktopMenuAction(
      context.l10n.text('Open in Yahoo Finance'),
      () => unawaited(
        launchUrlString('https://finance.yahoo.com/quote/$encoded'),
      ),
      icon: Icons.open_in_new_rounded,
    ),
    DesktopMenuAction(
      context.l10n.text('Open in Google Finance'),
      () => unawaited(_openGoogleFinance(symbol)),
      icon: Icons.search_rounded,
    ),
    DesktopMenuAction(
      context.l10n.text('Copy symbol'),
      () {
        unawaited(Clipboard.setData(ClipboardData(text: symbol)));
      },
      icon: Icons.copy_rounded,
    ),
    ...extraActions,
  ];
}
