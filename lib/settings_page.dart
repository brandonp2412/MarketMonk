import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/whats_new.dart';
import 'package:market_monk/csv_import.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _languageNames = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'pt-BR': 'Português (Brasil)',
  'pt-PT': 'Português (Portugal)',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'it': 'Italiano',
  'bn': 'বাংলা',
  'ur': 'اردو',
  'fa': 'فارسی',
  'hi': 'हिन्दी',
  'ar': 'العربية',
  'ru': 'Русский',
  'uk': 'Українська',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'tr': 'Türkçe',
  'th': 'ไทย',
  'vi': 'Tiếng Việt',
  'ja': '日本語',
  'ko': '한국어',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _brokerCsvInstructions = {
    'Tiger Brokers': [
      'Log into Tiger Trade (app or web).',
      'Go to Account (Me) → Statements.',
      'Pick a date range covering the trades to import.',
      'Enable "Display Detailed Trading Records" so individual fills are included, not just summary totals.',
      'Set the export format to CSV and download the statement.',
    ],
    'Interactive Brokers': [
      'Log into IBKR Client Portal.',
      'Go to Reports → Flex Queries, then click "+" next to Activity Flex Query.',
      'Under Sections, add Trades, set Options to Execution (one row per fill), and click Select All for the fields.',
      'Save the query, then set Period to a custom date range covering your trades (IBKR limits each run to 1 year).',
      'Set Format to CSV, then Run the query and download the file.',
    ],
  };

  Future<void> _importCsv(BuildContext context) async {
    BrokerCsvParser? selectedParser;
    BrokerCsvParser currentSelection = supportedBrokers.first;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.l10n.text('Select broker')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<BrokerCsvParser>(
                  value: currentSelection,
                  isExpanded: true,
                  items: supportedBrokers
                      .map(
                        (parser) => DropdownMenuItem(
                          value: parser,
                          child: Text(parser.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => currentSelection = value);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.text(
                    'How to get this CSV from {broker}:',
                    {'broker': currentSelection.name},
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                ...(_brokerCsvInstructions[currentSelection.name] ?? [])
                    .asMap()
                    .entries
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${entry.key + 1}. ${context.l10n.text(entry.value)}',
                        ),
                      ),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('Cancel')),
            ),
            TextButton(
              onPressed: () {
                selectedParser = currentSelection;
                Navigator.pop(context);
              },
              child: Text(context.l10n.text('Continue')),
            ),
          ],
        ),
      ),
    );

    if (selectedParser == null || !context.mounted) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (result == null || !context.mounted) return;

    ParseResult parsed;
    final contents = <String>[];
    try {
      for (final pickedFile in result.files) {
        final path = pickedFile.path;
        if (path == null) {
          throw StateError('Could not access ${pickedFile.name}');
        }
        contents.add(await File(path).readAsString());
      }
      parsed = parseBrokerCsvBatch(selectedParser!, contents);
    } catch (error) {
      if (!context.mounted) return;
      toast(
        context,
        context.l10n.text('Failed to parse CSV: {error}', {'error': error}),
      );
      return;
    }

    if (parsed.trades.isEmpty) {
      if (!context.mounted) return;
      BrokerCsvParser? detectedBroker;
      for (final content in contents) {
        detectedBroker = detectBrokerCsv(content, exclude: selectedParser);
        if (detectedBroker != null) break;
      }
      if (detectedBroker != null) {
        toast(
          context,
          'These files look like ${detectedBroker.name} CSVs. Select ${detectedBroker.name} and try again.',
        );
      } else {
        toast(
          context,
          context.l10n.text('No trades found in the selected files'),
        );
      }
      return;
    }

    bool confirmed = false;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n
              .text('Import {count} trades', {'count': parsed.trades.length}),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...parsed.trades.take(10).map(
                    (trade) => ListTile(
                      dense: true,
                      title: Text(
                        '${trade.symbol} — ${trade.tradeType.toUpperCase()}',
                      ),
                      subtitle: Text(
                        trade.tradeDate.toIso8601String().substring(0, 10),
                      ),
                      trailing: Text(
                        '${trade.quantity.abs().toStringAsFixed(2)} @ ${nativeCurrencySymbol(symbolCurrency(trade.symbol))}${trade.price.toStringAsFixed(2)}',
                      ),
                    ),
                  ),
              if (parsed.trades.length > 10)
                ListTile(
                  dense: true,
                  title: Text(
                    '... and ${parsed.trades.length - 10} more trades',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('Cancel')),
          ),
          TextButton(
            onPressed: () {
              confirmed = true;
              Navigator.pop(context);
            },
            child: Text(context.l10n.text('Import')),
          ),
        ],
      ),
    );

    if (!confirmed || !context.mounted) return;

    final accounts = context.read<AccountManager>();
    final profileId =
        await profileDataRepository.profileIdForName(accounts.activeAccount);
    final tradesCount = await importTrades(
      parsed.trades,
      profileId: profileId,
    );
    if (!context.mounted) return;
    final settings = context.read<SettingsState>();
    settings.notifyTradesImported();
    final allTrades = await profileDataRepository.readTrades(profileId);
    if (!context.mounted) return;
    final symbols = allTrades.map((trade) => trade.symbol).toSet();
    for (final symbol in symbols) {
      clearSyncCache(symbol);
    }
    await settings.syncTickers(symbols, syncCandles);
    if (!context.mounted) return;
    toast(
      context,
      context.l10n.text('Imported {count} trades', {'count': tradesCount}),
    );
  }

  Future<void> _importDatabase(BuildContext context) async {
    final accounts = context.read<AccountManager>();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'sqlite'],
    );
    if (!context.mounted || result == null) return;

    final selectedPath = result.files.single.path;
    if (selectedPath == null) {
      toast(
        context,
        context.l10n.text('Could not access the selected backup'),
      );
      return;
    }

    final sourceFile = File(selectedPath);
    final isArchive = p.extension(selectedPath).toLowerCase() == '.zip';
    try {
      if (isArchive) {
        await accounts.importBackup(sourceFile);
      } else {
        await validateMarketMonkSqliteFile(sourceFile);
        await accounts.importDatabase(sourceFile);
      }
    } catch (_) {
      if (context.mounted) {
        toast(context, context.l10n.text('Backup import failed'));
      }
      return;
    }

    if (!context.mounted) return;
    toast(
      context,
      context.l10n.text(
        isArchive
            ? 'Full backup restored'
            : 'Database imported into the active profile',
      ),
    );
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MyHomePage()),
        (_) => false,
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final accounts = context.read<AccountManager>();
    Navigator.pop(context);
    final tempDirectory = await getTemporaryDirectory();
    final workingDirectory =
        await tempDirectory.createTemp('market-monk-backup-');
    try {
      final archive = await accounts.exportBackup(workingDirectory);
      final result = await FilePicker.saveFile(
        fileName: marketMonkBackupFileName,
        bytes: await archive.readAsBytes(),
      );
      if (result == null) return;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await archive.copy(result);
      }
    } catch (_) {
      if (context.mounted) {
        toast(context, context.l10n.text('Backup export failed'));
      }
    } finally {
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _showCurrencyPicker(
    BuildContext context,
    SettingsState settings,
  ) async {
    var selected = Set<String>.from(settings.visibleCurrencies)..add('USD');

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.l10n.text('Display currencies')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: supportedCurrencies
                  .map(
                    (currencyCode) => CheckboxListTile(
                      dense: true,
                      title: Text(currencyCode),
                      value: selected.contains(currencyCode),
                      onChanged: currencyCode == 'USD'
                          ? null
                          : (checked) {
                              setState(() {
                                if (checked == true) {
                                  selected.add(currencyCode);
                                } else {
                                  selected.remove(currencyCode);
                                }
                              });
                            },
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('Cancel')),
            ),
            TextButton(
              onPressed: () async {
                await settings.setVisibleCurrencies(
                  supportedCurrencies.where(selected.contains).toList(),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.l10n.text('Save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIbkrSettings(BuildContext context) async {
    final accounts = context.read<AccountManager>();
    final account = accounts.activeAccount;
    await showDialog<void>(
      context: context,
      builder: (_) => _IbkrSettingsDialog(
        accounts: accounts,
        account: account,
        current: accounts.ibkrConfigFor(account),
      ),
    );
  }

  Future<void> _syncAllTickers(BuildContext context) async {
    final settings = context.read<SettingsState>();
    if (settings.syncInProgress) return;

    final accounts = context.read<AccountManager>();
    final config = accounts.ibkrConfigFor();
    final profileId =
        await profileDataRepository.profileIdForName(accounts.activeAccount);
    final trades = await profileDataRepository.readTrades(profileId);
    final symbols = config.enabled
        ? (await IbkrApiClient(config).fetchPortfolio())
            .positions
            .where((position) => position.securityType == 'STK')
            .map((position) => position.symbol)
            .toSet()
        : trades.map((trade) => trade.symbol).toSet();
    for (final symbol in symbols) {
      clearSyncCache(symbol);
    }
    await settings.syncTickers(symbols, syncCandles);
    if (config.enabled) accounts.requestIbkrRefresh();
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Widget _desktopSettingsCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: theme.colorScheme.outlineVariant),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSettings(
    SettingsState settings,
    Future<PackageInfo> packageInfo,
  ) {
    final accounts = context.watch<AccountManager>();
    final ibkrConfig = accounts.ibkrConfigFor();

    final appearance = _desktopSettingsCard(
      icon: Icons.palette_outlined,
      title: context.l10n.text('Appearance'),
      children: [
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(context.l10n.text('System')),
              icon: const Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(context.l10n.text('Dark')),
              icon: const Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(context.l10n.text('Light')),
              icon: const Icon(Icons.light_mode),
            ),
          ],
          selected: {settings.theme},
          onSelectionChanged: (selection) async {
            final value = selection.first;
            await settings.setTheme(value);
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: Text(context.l10n.text('Language')),
          trailing: DropdownButton<String>(
            value: settings.languageCode ?? 'system',
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(context.l10n.text('System default')),
              ),
              ..._languageNames.entries.map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              ),
            ],
            onChanged: (value) => settings.setLanguageCode(
              value == 'system' ? null : value,
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: settings.systemColors
              ? const Icon(Icons.color_lens)
              : const Icon(Icons.color_lens_outlined),
          title: Text(context.l10n.text('System color scheme')),
          trailing: Switch(
            value: settings.systemColors,
            onChanged: settings.setSystemColors,
          ),
          onTap: () => settings.setSystemColors(!settings.systemColors),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.contrast),
          title: Text(context.l10n.text('Pure black (AMOLED)')),
          subtitle: Text(
            context.l10n.text('Use pure black for AMOLED displays'),
          ),
          trailing: Switch(
            value: settings.pureBlack,
            onChanged: settings.setPureBlack,
          ),
          onTap: () => settings.setPureBlack(!settings.pureBlack),
        ),
        if (!settings.systemColors) _ColorPicker(settings: settings),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: settings.dateFormat,
          items: const [
            DropdownMenuItem(value: 'yyyy-MM-dd', child: Text('yyyy-MM-dd')),
            DropdownMenuItem(value: 'd/M/yy', child: Text('d/M/yy')),
            DropdownMenuItem(value: 'M/d/yy', child: Text('M/d/yy')),
            DropdownMenuItem(value: 'd-M-yy', child: Text('d-M-yy')),
            DropdownMenuItem(value: 'M-d-yy', child: Text('M-d-yy')),
            DropdownMenuItem(value: 'd.M.yy', child: Text('d.M.yy')),
            DropdownMenuItem(value: 'M.d.yy', child: Text('M.d.yy')),
          ],
          onChanged: (value) => settings.setDateFormat(value ?? 'd/M/yy'),
          decoration: InputDecoration(
            labelText: context.l10n.text(
              'Date format ({example})',
              {
                'example':
                    DateFormat(settings.dateFormat).format(DateTime.now()),
              },
            ),
          ),
        ),
      ],
    );

    final charts = _desktopSettingsCard(
      icon: Icons.insights_outlined,
      title: context.l10n.text('Charts'),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: settings.showMarketClosed
              ? const Icon(Icons.schedule)
              : const Icon(Icons.schedule_outlined),
          title: Text(context.l10n.text('Market closed indicator')),
          trailing: Switch(
            value: settings.showMarketClosed,
            onChanged: settings.setShowMarketClosed,
          ),
          onTap: () => settings.setShowMarketClosed(!settings.showMarketClosed),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insights),
          title: Text(context.l10n.text('Curve line graphs')),
          trailing: Switch(
            value: settings.curveLines,
            onChanged: settings.setCurveLines,
          ),
          onTap: () => settings.setCurveLines(!settings.curveLines),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text(context.l10n.text('Curve smoothness'))),
              SizedBox(
                width: 220,
                child: Slider(
                  value: settings.curveSmoothness,
                  onChanged: settings.setCurveSmoothness,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: TickerLine(
            spots: const [
              FlSpot(0, 0.13),
              FlSpot(1, 5),
              FlSpot(2, 2),
              FlSpot(3, 10),
              FlSpot(4, 5),
            ],
            dates: [
              DateTime.now().subtract(const Duration(days: 4)),
              DateTime.now().subtract(const Duration(days: 3)),
              DateTime.now().subtract(const Duration(days: 2)),
              DateTime.now().subtract(const Duration(days: 1)),
              DateTime.now(),
            ],
          ),
        ),
      ],
    );

    final accountSettings = _desktopSettingsCard(
      icon: Icons.account_balance_wallet_outlined,
      title: context.l10n.text('Accounts'),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.manage_accounts),
          title: Text(context.l10n.text('Manage accounts')),
          subtitle: Text(accounts.activeAccount),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountsPage()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.currency_exchange),
          title: Text(context.l10n.text('Currencies')),
          subtitle: Text(settings.visibleCurrencies.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showCurrencyPicker(context, settings),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance),
          title: Text(context.l10n.text('Interactive Brokers')),
          subtitle: Text(
            ibkrConfig.enabled
                ? context.l10n.text(
                    'IBKR portfolio source • {url}',
                    {'url': ibkrConfig.baseUrl},
                  )
                : context.l10n.text('Use a self-hosted IBKR portfolio API'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showIbkrSettings(context),
        ),
      ],
    );

    final data = _desktopSettingsCard(
      icon: Icons.storage_outlined,
      title: context.l10n.text('Data'),
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _exportBackup(context),
              icon: const Icon(Icons.download),
              label: Text(context.l10n.text('Export database')),
            ),
            OutlinedButton.icon(
              onPressed: () => _importDatabase(context),
              icon: const Icon(Icons.upload),
              label: Text(context.l10n.text('Import database')),
            ),
            OutlinedButton.icon(
              onPressed: () => _importCsv(context),
              icon: const Icon(Icons.table_chart),
              label: Text(context.l10n.text('Import CSV')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap:
              settings.syncInProgress ? null : () => _syncAllTickers(context),
          leading: settings.syncInProgress
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  settings.syncFailed > 0 ? Icons.sync_problem : Icons.sync,
                ),
          title: Text(context.l10n.text('Sync')),
          subtitle: Text(
            settings.syncInProgress
                ? context.l10n.text(
                    'Syncing {symbol} ({completed}/{total})',
                    {
                      'symbol': settings.syncingSymbol ?? '',
                      'completed': settings.syncCompleted,
                      'total': settings.syncTotal,
                    },
                  )
                : settings.syncTotal == 0
                    ? context.l10n.text('No sync running')
                    : settings.syncFailed == 0
                        ? context.l10n.text(
                            'Last sync completed {completed}/{total}',
                            {
                              'completed': settings.syncCompleted,
                              'total': settings.syncTotal,
                            },
                          )
                        : context.l10n.text(
                            'Last sync completed with {failed} failed',
                            {'failed': settings.syncFailed},
                          ),
          ),
        ),
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(context.l10n.text('Delete all data')),
          subtitle: Text(
            context.l10n.text(
              'Permanently delete all holdings, trades, and candles',
            ),
          ),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(context.l10n.text('Delete all data?')),
                content: Text(
                  context.l10n.text(
                    'This will permanently delete all holdings, trades, and chart data. This cannot be undone.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(context.l10n.text('Cancel')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(context.l10n.text('Delete')),
                  ),
                ],
              ),
            );
            if (confirmed != true || !mounted) return;
            final accounts = context.read<AccountManager>();
            final profileId = await profileDataRepository
                .profileIdForName(accounts.activeAccount);
            await profileDataRepository.clearTrades(profileId);
            await marketDataDatabase
                .delete(marketDataDatabase.unifiedCandles)
                .go();
            clearAllSyncCache();
            if (!mounted) return;
            toast(context, context.l10n.text('All data deleted'));
          },
        ),
      ],
    );

    final about = _desktopSettingsCard(
      icon: Icons.info_outline,
      title: context.l10n.text('About'),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.new_releases_outlined),
          title: Text(context.l10n.text("What's New")),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WhatsNew()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(context.l10n.text('Version')),
          subtitle: FutureBuilder(
            future: packageInfo,
            builder: (context, snapshot) =>
                Text(snapshot.data?.version ?? '1.0.0'),
          ),
          onTap: () async {
            const url = 'https://github.com/brandonp2412/MarketMonk/releases';
            if (await canLaunchUrlString(url)) await launchUrlString(url);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person),
          title: Text(context.l10n.text('Author')),
          subtitle: const Text('Brandon Dick'),
          onTap: () async {
            const url = 'https://github.com/brandonp2412';
            if (await canLaunchUrlString(url)) await launchUrlString(url);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code),
          title: Text(context.l10n.text('Source code')),
          subtitle: Text(context.l10n.text('Check it out on GitHub')),
          onTap: () async {
            const url = 'https://github.com/brandonp2412/MarketMonk';
            if (await canLaunchUrlString(url)) await launchUrlString(url);
          },
        ),
      ],
    );

    final cards = [
      appearance,
      accountSettings,
      charts,
      data,
      if (Platform.isAndroid || Platform.isWindows) about,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 920;
        final content = twoColumns
            ? Row(
                key: const Key('desktop-settings-two-column'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 16),
                        cards[2],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        cards[1],
                        const SizedBox(height: 16),
                        cards[3],
                        if (cards.length > 4) ...[
                          const SizedBox(height: 16),
                          cards[4],
                        ],
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                key: const Key('desktop-settings-single-column'),
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    cards[index],
                    if (index != cards.length - 1) const SizedBox(height: 16),
                  ],
                ],
              );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: content,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = PackageInfo.fromPlatform();
    final settings = context.watch<SettingsState>();

    if (isDesktopLayout(context)) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.text('Settings'))),
        body: _buildDesktopSettings(settings, packageInfo),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('Settings'))),
      body: ListView(
        children: [
          _sectionHeader(context.l10n.text('Appearance')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(context.l10n.text('System')),
                  icon: const Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(context.l10n.text('Dark')),
                  icon: const Icon(Icons.dark_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(context.l10n.text('Light')),
                  icon: const Icon(Icons.light_mode),
                ),
              ],
              selected: {settings.theme},
              onSelectionChanged: (selection) async {
                final value = selection.first;
                final settings = context.read<SettingsState>();
                await settings.setTheme(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.l10n.text('Language')),
            trailing: DropdownButton<String>(
              value: settings.languageCode ?? 'system',
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(context.l10n.text('System default')),
                ),
                ..._languageNames.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                ),
              ],
              onChanged: (value) => settings.setLanguageCode(
                value == 'system' ? null : value,
              ),
            ),
          ),
          Tooltip(
            message: context.l10n.text(
              'Use the primary color of your device for the app',
            ),
            child: ListTile(
              title: Text(context.l10n.text('System color scheme')),
              leading: settings.systemColors
                  ? const Icon(Icons.color_lens)
                  : const Icon(Icons.color_lens_outlined),
              onTap: () => settings.setSystemColors(!settings.systemColors),
              trailing: Switch(
                value: settings.systemColors,
                onChanged: (value) => settings.setSystemColors(value),
              ),
            ),
          ),
          ListTile(
            title: Text(context.l10n.text('Pure black (AMOLED)')),
            leading: const Icon(Icons.contrast),
            subtitle:
                Text(context.l10n.text('Use pure black for AMOLED displays')),
            trailing: Switch(
              value: settings.pureBlack,
              onChanged: (value) => settings.setPureBlack(value),
            ),
            onTap: () => settings.setPureBlack(!settings.pureBlack),
          ),
          if (!settings.systemColors) _ColorPicker(settings: settings),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Tooltip(
              message:
                  context.l10n.text('How dates are displayed below graphs'),
              child: DropdownButtonFormField<String>(
                initialValue: settings.dateFormat,
                items: const [
                  DropdownMenuItem(
                    value: "yyyy-MM-dd",
                    child: Text("yyyy-MM-dd"),
                  ),
                  DropdownMenuItem(value: "d/M/yy", child: Text("d/M/yy")),
                  DropdownMenuItem(value: "M/d/yy", child: Text("M/d/yy")),
                  DropdownMenuItem(value: "d-M-yy", child: Text("d-M-yy")),
                  DropdownMenuItem(value: "M-d-yy", child: Text("M-d-yy")),
                  DropdownMenuItem(value: "d.M.yy", child: Text("d.M.yy")),
                  DropdownMenuItem(value: "M.d.yy", child: Text("M.d.yy")),
                ],
                onChanged: (value) => settings.setDateFormat(value ?? 'd/M/yy'),
                decoration: InputDecoration(
                  labelText: context.l10n.text(
                    'Date format ({example})',
                    {
                      'example': DateFormat(settings.dateFormat)
                          .format(DateTime.now()),
                    },
                  ),
                ),
              ),
            ),
          ),
          _sectionHeader(context.l10n.text('Charts')),
          Tooltip(
            message: context.l10n.text(
              'Show a badge on the chart when the market is closed (weekends)',
            ),
            child: ListTile(
              title: Text(context.l10n.text('Market closed indicator')),
              leading: settings.showMarketClosed
                  ? const Icon(Icons.schedule)
                  : const Icon(Icons.schedule_outlined),
              onTap: () =>
                  settings.setShowMarketClosed(!settings.showMarketClosed),
              trailing: Switch(
                value: settings.showMarketClosed,
                onChanged: (value) => settings.setShowMarketClosed(value),
              ),
            ),
          ),
          Tooltip(
            message: context.l10n.text('Use wavy curves in the graphs page'),
            child: ListTile(
              title: Text(context.l10n.text('Curve line graphs')),
              leading: const Icon(Icons.insights),
              onTap: () => settings.setCurveLines(!settings.curveLines),
              trailing: Switch(
                value: settings.curveLines,
                onChanged: (value) => settings.setCurveLines(value),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.text('Curve smoothness'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Slider(
                value: settings.curveSmoothness,
                inactiveColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.24),
                onChanged: (value) {
                  runDetachedTask(
                    settings.setCurveSmoothness(value),
                    'Failed to save curve smoothness',
                  );
                },
              ),
            ],
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: TickerLine(
              spots: const [
                FlSpot(0, 0.13),
                FlSpot(1, 5),
                FlSpot(2, 2),
                FlSpot(3, 10),
                FlSpot(4, 5),
              ],
              dates: [
                DateTime.now().subtract(const Duration(days: 4)),
                DateTime.now().subtract(const Duration(days: 3)),
                DateTime.now().subtract(const Duration(days: 2)),
                DateTime.now().subtract(const Duration(days: 1)),
                DateTime.now(),
              ],
            ),
          ),
          _sectionHeader(context.l10n.text('Accounts')),
          ListTile(
            leading: const Icon(Icons.manage_accounts),
            title: Text(context.l10n.text('Manage accounts')),
            subtitle: Text(context.watch<AccountManager>().activeAccount),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(context.l10n.text('Currencies')),
            subtitle: Text(settings.visibleCurrencies.join(', ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCurrencyPicker(context, settings),
          ),
          Builder(
            builder: (context) {
              final accounts = context.watch<AccountManager>();
              final config = accounts.ibkrConfigFor();
              return ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text(context.l10n.text('Interactive Brokers')),
                subtitle: Text(
                  config.enabled
                      ? context.l10n.text(
                          'IBKR portfolio source • {url}',
                          {'url': config.baseUrl},
                        )
                      : context.l10n
                          .text('Use a self-hosted IBKR portfolio API'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showIbkrSettings(context),
              );
            },
          ),
          _sectionHeader(context.l10n.text('Data')),
          Tooltip(
            message:
                context.l10n.text('Download a full backup of every profile'),
            child: ListTile(
              leading: const Icon(Icons.download),
              title: Text(context.l10n.text('Export database')),
              onTap: () => _exportBackup(context),
            ),
          ),
          Tooltip(
            message: context.l10n.text('Import a .sqlite database'),
            child: ListTile(
              leading: const Icon(Icons.upload),
              title: Text(context.l10n.text('Import database')),
              onTap: () => _importDatabase(context),
            ),
          ),
          Tooltip(
            message:
                context.l10n.text('Import holdings from a broker CSV export'),
            child: ListTile(
              leading: const Icon(Icons.table_chart),
              title: Text(context.l10n.text('Import CSV')),
              onTap: () => _importCsv(context),
            ),
          ),
          ListTile(
            onTap:
                settings.syncInProgress ? null : () => _syncAllTickers(context),
            leading: settings.syncInProgress
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    settings.syncFailed > 0 ? Icons.sync_problem : Icons.sync,
                  ),
            title: Text(context.l10n.text('Sync')),
            subtitle: settings.syncInProgress
                ? Text(
                    context.l10n.text(
                      'Syncing {symbol} ({completed}/{total})',
                      {
                        'symbol': settings.syncingSymbol ?? '',
                        'completed': settings.syncCompleted,
                        'total': settings.syncTotal,
                      },
                    ),
                  )
                : Text(
                    settings.syncTotal == 0
                        ? context.l10n.text('No sync running')
                        : settings.syncFailed == 0
                            ? context.l10n.text(
                                'Last sync completed {completed}/{total}',
                                {
                                  'completed': settings.syncCompleted,
                                  'total': settings.syncTotal,
                                },
                              )
                            : context.l10n.text(
                                'Last sync completed with {failed} failed',
                                {'failed': settings.syncFailed},
                              ),
                  ),
          ),
          Tooltip(
            message: context.l10n.text(
              'Permanently delete all holdings, trades, and candles',
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever),
              title: Text(context.l10n.text('Delete all data')),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(context.l10n.text('Delete all data?')),
                    content: Text(
                      context.l10n.text(
                        'This will permanently delete all holdings, trades, and chart data. This cannot be undone.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.l10n.text('Cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(context.l10n.text('Delete')),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                final accounts = context.read<AccountManager>();
                final profileId = await profileDataRepository
                    .profileIdForName(accounts.activeAccount);
                await profileDataRepository.clearTrades(profileId);
                await marketDataDatabase
                    .delete(marketDataDatabase.unifiedCandles)
                    .go();
                clearAllSyncCache();
                if (!context.mounted) return;
                toast(context, context.l10n.text('All data deleted'));
              },
            ),
          ),
          if (Platform.isAndroid || Platform.isWindows) ...[
            const SizedBox(height: 16),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.l10n.text('About'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(context.l10n.text("What's New")),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WhatsNew()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.l10n.text('Version')),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) =>
                    Text(snapshot.data?.version ?? "1.0.0"),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url =
                    'https://github.com/brandonp2412/MarketMonk/releases';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: Text(context.l10n.text('Author')),
              leading: const Icon(Icons.person),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) => const Text("Brandon Dick"),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url = 'https://github.com/brandonp2412';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: Text(context.l10n.text('License')),
              leading: const Icon(Icons.balance),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) => const Text("MIT"),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url =
                    'https://github.com/brandonp2412/MarketMonk?tab=MIT-1-ov-file#readme';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: Text(context.l10n.text('Source code')),
              leading: const Icon(Icons.code),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) =>
                    Text(context.l10n.text('Check it out on GitHub')),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url = 'https://github.com/brandonp2412/MarketMonk';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: Text(context.l10n.text('Donate')),
              leading: const Icon(Icons.favorite_outline),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) =>
                    Text(context.l10n.text('Help support this project')),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url = 'https://github.com/sponsors/brandonp2412';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _IbkrSettingsDialog extends StatefulWidget {
  final AccountManager accounts;
  final String account;
  final IbkrAccountConfig current;

  const _IbkrSettingsDialog({
    required this.accounts,
    required this.account,
    required this.current,
  });

  @override
  State<_IbkrSettingsDialog> createState() => _IbkrSettingsDialogState();
}

class _IbkrSettingsDialogState extends State<_IbkrSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late bool _enabled;
  var _checking = false;
  String? _status;
  var _statusOk = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.current.baseUrl);
    _tokenController = TextEditingController(text: widget.current.token);
    _enabled = widget.current.enabled;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  IbkrAccountConfig _config({required bool enabled}) => IbkrAccountConfig(
        enabled: enabled,
        baseUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
      );

  Future<bool> _checkConnection() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await IbkrApiClient(_config(enabled: true)).testConnection();
      if (!mounted) return false;
      setState(() {
        _checking = false;
        _statusOk = true;
        _status = context.l10n.text('Connected to IBKR');
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _checking = false;
        _statusOk = false;
        _status = error.toString().replaceFirst('Bad state: ', '');
      });
      return false;
    }
  }

  Future<void> _save() async {
    final config = _config(enabled: _enabled);
    if (_enabled && !await _checkConnection()) return;
    await widget.accounts.setIbkrConfig(widget.account, config);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          context.l10n.text(
            'Interactive Brokers — {account}',
            {'account': widget.account},
          ),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.text('Use IBKR portfolio data')),
                  subtitle: Text(
                    context.l10n.text(
                      'Positions, current valuations, and held-stock history prefer your self-hosted IBKR API. Yahoo remains the fallback for unavailable history and other symbols.',
                    ),
                  ),
                  value: _enabled,
                  onChanged: _checking
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                TextField(
                  controller: _urlController,
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('API URL'),
                    hintText: 'https://ibkr.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  enabled: !_checking,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Bearer token'),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _statusOk ? Icons.check_circle : Icons.error_outline,
                        color: _statusOk
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status!)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _checking ? null : () => Navigator.pop(context),
            child: Text(context.l10n.text('Cancel')),
          ),
          TextButton(
            onPressed: _checking ? null : _checkConnection,
            child: Text(context.l10n.text('Test')),
          ),
          FilledButton(
            onPressed: _checking ? null : _save,
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.text('Save')),
          ),
        ],
      );
}

class _ColorPicker extends StatelessWidget {
  static const _colors = [
    Color(0xFF2B7A78), // default teal
    Color(0xFF6750A4), // purple
    Color(0xFF1976D2), // blue
    Color(0xFF388E3C), // green
    Color(0xFFD32F2F), // red
    Color(0xFFF57C00), // orange
    Color(0xFF7B1FA2), // violet
    Color(0xFF0097A7), // cyan
    Color(0xFF5D4037), // brown
    Color(0xFF455A64), // blue-grey
  ];

  final SettingsState settings;

  const _ColorPicker({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('App color'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colors.map((color) {
              final isSelected = settings.seedColor == color;
              return GestureDetector(
                onTap: () => settings.setSeedColor(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
