import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/csv_import.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:market_monk/theme_color_wheel.dart';
import 'package:market_monk/whats_new.dart';
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

const _dateFormatOptions = <String>[
  'yyyy-MM-dd',
  'yyyy/MM/dd',
  'yyyy.MM.dd',
  'd/M/yy',
  'M/d/yy',
  'dd/MM/yyyy',
  'MM/dd/yyyy',
  'd-M-yy',
  'M-d-yy',
  'dd-MM-yyyy',
  'MM-dd-yyyy',
  'd.M.yy',
  'M.d.yy',
  'dd.MM.yyyy',
  'd MMM yyyy',
  'MMM d, yyyy',
  'd MMM yy',
  'MMM d, yy',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.isActive = true, this.onClose});
  final VoidCallback? onClose;
  final bool isActive;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _desktopContentMaxWidth = 1240.0;
  static const _desktopSearchOptions = <String, List<String>>{
    'General': ['Language', 'Start page', 'Date format', 'Hide dollar amounts'],
    'Appearance': ['Theme', 'System color scheme', 'Pure black (AMOLED)'],
    'Charts': [
      'Curve line graphs',
      'Curve smoothness',
      'Chart gridlines',
      'Chart shading',
    ],
    'Keyboard': ['Vi key bindings', 'Reset to defaults'],
    'Accounts': ['Manage accounts', 'Currencies', 'Interactive Brokers'],
    'Data': ['Export database', 'Import database', 'Import CSV', 'Sync'],
    'Danger zone': ['Delete all data'],
    'About': ["What's New", 'Version', 'Author', 'Source code'],
  };
  static const _mobileSearchOptions = <String, List<String>>{
    'General': ['Language', 'Start page', 'Date format', 'Hide dollar amounts'],
    'Appearance': ['Theme', 'System color scheme', 'Pure black (AMOLED)'],
    'Charts': [
      'Rolling average',
      'Candles',
      'Curve line graphs',
      'Curve smoothness',
      'Chart gridlines',
      'Chart shading',
    ],
    'Keyboard': ['Vi key bindings', 'Reset to defaults'],
    'Accounts': ['Manage accounts', 'Currencies', 'Interactive Brokers'],
    'Data': ['Export database', 'Import database', 'Import CSV', 'Sync'],
    'Danger zone': ['Delete all data'],
    'About': [
      "What's New",
      'Version',
      'Author',
      'License',
      'Source code',
      'Donate',
    ],
  };

  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _searchFocus = FocusNode();
  late final _viTarget = ViTarget(
    requestSearch: _searchFocus.requestFocus,
    moveFocus: (delta) {
      final scope = FocusScope.of(context);
      if (delta > 0) {
        scope.nextFocus();
      } else {
        scope.previousFocus();
      }
    },
  );

  void _syncViTarget() {
    if (widget.isActive) {
      ViNavigation.instance.target = _viTarget;
    } else if (identical(ViNavigation.instance.target, _viTarget)) {
      ViNavigation.instance.target = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncViTarget();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncViTarget();
  }

  @override
  void dispose() {
    if (identical(ViNavigation.instance.target, _viTarget))
      ViNavigation.instance.target = null;
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(String section, String option) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final aliases = switch (option) {
      'Interactive Brokers' => 'IBKR broker',
      'Theme' => 'dark light system appearance',
      'Currencies' => 'currency exchange',
      'Export database' => 'backup',
      'Import database' => 'backup restore',
      'Hide dollar amounts' => 'privacy hide balances mask amounts',
      'Sync' => 'refresh refresh prices update prices',
      'Rolling average' => 'moving average',
      'Candles' => 'candlestick candlesticks',
      'Curve line graphs' => 'graph lines',
      'Start page' => 'home launch default tab navigation',
      'Chart gridlines' => 'grid guide horizontal lines',
      'Chart shading' => 'fill shaded area gradient',
      'Vi key bindings' => 'vi mode hotkeys keyboard shortcuts',
      'Reset to defaults' => 'restore default vi bindings',
      _ => '',
    };
    final searchable =
        '${context.l10n.text(section)} ${context.l10n.text(option)} $aliases'
            .toLowerCase();
    return query.split(RegExp(r'\s+')).every(searchable.contains);
  }

  bool _hasMatches(String section, List<String> options) =>
      options.any((option) => _matchesSearch(section, option));

  bool _hasAnyMatches(Map<String, List<String>> sections) =>
      sections.entries.any((entry) => _hasMatches(entry.key, entry.value));

  Widget _searchField() => Padding(
        padding: EdgeInsets.fromLTRB(
          isDesktopLayout(context) ? 24 : 16,
          12,
          isDesktopLayout(context) ? 24 : 16,
          8,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _desktopContentMaxWidth,
            ),
            child: TextField(
              key: const Key('settings-search'),
              focusNode: _searchFocus,
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: context.l10n.text('Search settings'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.text('Clear search'),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      );

  Widget _noSearchResults() =>
      Center(child: Text(context.l10n.text('No matching settings')));
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
                  context.l10n.text('How to get this CSV from {broker}:', {
                    'broker': currentSelection.name,
                  }),
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
    if (result.isEmpty || !context.mounted) return;

    ParseResult parsed;
    final contents = <String>[];
    try {
      for (final pickedFile in result) {
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
          context.l10n.text('Import {count} trades', {
            'count': parsed.trades.length,
          }),
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
                        '${trade.quantity.abs().toStringAsFixed(2)} @ ${trade.price.toStringAsFixed(2)} ${trade.rawCurrency ?? 'unit unknown'}',
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
    final profileId = await profileDataRepository.profileIdForName(
      accounts.activeAccount,
    );
    final tradesCount = await importTrades(parsed.trades, profileId: profileId);
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
    if (!context.mounted || result.isEmpty) return;

    final selectedPath = result.single.path;
    if (selectedPath == null) {
      toast(context, context.l10n.text('Could not access the selected backup'));
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
        adaptivePageRoute(context, builder: (_) => const MyHomePage()),
        (_) => false,
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final accounts = context.read<AccountManager>();
    if (!isDesktopLayout(context)) Navigator.pop(context);
    final tempDirectory = await getTemporaryDirectory();
    final workingDirectory = await tempDirectory.createTemp(
      'market-monk-backup-',
    );
    try {
      final archive = await accounts.exportBackup(workingDirectory);
      final result = await FilePicker.saveFile(
        fileName: marketMonkBackupFileName,
        bytes: await archive.readAsBytes(),
      );
      if (result == null) return;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await archive.copy(result.toFilePath());
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
    var selected = Set<String>.from(settings.visibleCurrencies);

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
                      onChanged: selected.length == 1 &&
                              selected.contains(currencyCode)
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
    final profileId = await profileDataRepository.profileIdForName(
      accounts.activeAccount,
    );
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
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  Widget _languageDropdown(
    SettingsState settings, {
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
  }) {
    return Padding(
      padding: padding,
      child: DropdownButtonFormField<String>(
        key: ValueKey(settings.languageCode ?? 'system'),
        initialValue: settings.languageCode ?? 'system',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.text('Language'),
          prefixIcon: const Icon(Icons.language),
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: 'system',
            child: Text(context.l10n.text('System default')),
          ),
          ..._languageNames.entries.map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) =>
            settings.setLanguageCode(value == 'system' ? null : value),
      ),
    );
  }

  Widget _startPageDropdown(
    SettingsState settings, {
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
  }) =>
      Padding(
        padding: padding,
        child: DropdownButtonFormField<int>(
          key: const Key('settings-start-page'),
          initialValue: settings.startPage,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.l10n.text('Start page'),
            prefixIcon: const Icon(Icons.home_outlined),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 0,
              child: Text(context.l10n.text('Charts')),
            ),
            DropdownMenuItem(
              value: 1,
              child: Text(context.l10n.text('Portfolio')),
            ),
            DropdownMenuItem(
              value: 2,
              child: Text(context.l10n.text('Holdings')),
            ),
          ],
          onChanged: (value) async {
            if (value != null) await settings.setStartPage(value);
          },
        ),
      );

  Widget _chartSwitch({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    EdgeInsetsGeometry? padding,
  }) =>
      ListTile(
        key: Key('settings-${label.toLowerCase().replaceAll(' ', '-')}'),
        contentPadding: padding,
        leading: Icon(icon),
        title: Text(context.l10n.text(label)),
        trailing: Switch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );

  Widget _viBindingRow(SettingsState settings, ViAction action) {
    final label = settings.viBindings[action] ?? kDefaultViBindings[action]!;
    return ListTile(
      key: Key('settings-vi-binding-${action.name}'),
      contentPadding: EdgeInsets.zero,
      title: Text(context.l10n.text(action.label)),
      trailing: Text(
        viKeyDisplayName(label),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
      ),
      onTap: () => _showViRebindDialog(context, settings, action),
    );
  }

  void _showViRebindDialog(
    BuildContext context,
    SettingsState settings,
    ViAction action,
  ) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _ViRebindDialog(settings: settings, action: action),
      ),
    );
  }

  Widget _chartPreview(SettingsState settings, {required double height}) {
    const prices = <double>[
      82,
      86,
      83,
      90,
      96,
      92,
      101,
      98,
      105,
      110,
      106,
      114,
    ];
    final today = DateUtils.dateOnly(DateTime.now());
    return SizedBox(
      key: const Key('settings-chart-preview'),
      height: height,
      child: TickerLine(
        spots: [
          for (var i = 0; i < prices.length; i++)
            MarketLineChartPoint(i.toDouble(), prices[i], column: i),
        ],
        dates: [
          for (var i = 0; i < prices.length; i++)
            today.subtract(Duration(days: prices.length - i - 1)),
        ],
        candles: [
          for (var i = 0; i < prices.length; i++)
            MarketCandlePoint(
              column: i,
              open: i == 0 ? 80 : prices[i - 1],
              high: math.max(prices[i], i == 0 ? 80 : prices[i - 1]) + 3,
              low: math.min(prices[i], i == 0 ? 80 : prices[i - 1]) - 3,
              close: prices[i],
            ),
        ],
        showRollingAverage: settings.showRollingAverage,
        showCandlesticks: settings.showCandlesticks,
      ),
    );
  }

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
                Text(title, style: theme.textTheme.titleLarge),
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

    final general = _desktopSettingsCard(
      icon: Icons.tune_outlined,
      title: context.l10n.text('General'),
      children: [
        const SizedBox(height: 8),
        if (_matchesSearch('General', 'Language')) ...[
          _languageDropdown(settings, padding: EdgeInsets.zero),
          const SizedBox(height: 8),
        ],
        if (_matchesSearch('General', 'Start page')) ...[
          _startPageDropdown(settings, padding: EdgeInsets.zero),
          const SizedBox(height: 8),
        ],
        if (_matchesSearch('General', 'Date format'))
          DropdownButtonFormField<String>(
            initialValue: settings.dateFormat,
            items: _dateFormatOptions
                .map(
                  (format) => DropdownMenuItem(
                    value: format,
                    child: Text(format),
                  ),
                )
                .toList(),
            onChanged: (value) => settings.setDateFormat(value ?? 'd/M/yy'),
            decoration: InputDecoration(
              labelText: context.l10n.text('Date format ({example})', {
                'example':
                    DateFormat(settings.dateFormat).format(DateTime.now()),
              }),
            ),
          ),
        if (_matchesSearch('General', 'Hide dollar amounts'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              settings.hideDollarAmounts
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            title: Text(context.l10n.text('Hide dollar amounts')),
            trailing: Switch(
              value: settings.hideDollarAmounts,
              onChanged: settings.setHideDollarAmounts,
            ),
            onTap: () =>
                settings.setHideDollarAmounts(!settings.hideDollarAmounts),
          ),
      ],
    );

    final appearance = _desktopSettingsCard(
      icon: Icons.palette_outlined,
      title: context.l10n.text('Appearance'),
      children: [
        const SizedBox(height: 8),
        if (_matchesSearch('Appearance', 'Theme'))
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
        const SizedBox(height: 16),
        if (_matchesSearch('Appearance', 'System color scheme'))
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
        if (_matchesSearch('Appearance', 'Pure black (AMOLED)'))
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
        if (!settings.systemColors &&
            _matchesSearch('Appearance', 'System color scheme'))
          _ColorPicker(settings: settings),
        const SizedBox(height: 8),
      ],
    );

    final charts = _desktopSettingsCard(
      icon: Icons.insights_outlined,
      title: context.l10n.text('Charts'),
      children: [
        if (_matchesSearch('Charts', 'Chart gridlines'))
          _chartSwitch(
            label: 'Chart gridlines',
            icon: Icons.grid_on_outlined,
            value: settings.showChartGridlines,
            onChanged: settings.setShowChartGridlines,
            padding: EdgeInsets.zero,
          ),
        if (_matchesSearch('Charts', 'Chart shading'))
          _chartSwitch(
            label: 'Chart shading',
            icon: Icons.gradient_outlined,
            value: settings.fillChartArea,
            onChanged: settings.setFillChartArea,
            padding: EdgeInsets.zero,
          ),
        if (_matchesSearch('Charts', 'Curve line graphs'))
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
        if (_matchesSearch('Charts', 'Curve smoothness'))
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text(context.l10n.text('Curve smoothness'))),
                SizedBox(
                  width: 220,
                  child: Slider(
                    value: settings.curveSmoothness,
                    divisions: 20,
                    onChanged: settings.setCurveSmoothness,
                  ),
                ),
              ],
            ),
          ),
        if (_hasMatches('Charts', _desktopSearchOptions['Charts']!))
          _chartPreview(settings, height: 180),
      ],
    );

    final keyboard = _desktopSettingsCard(
      icon: Icons.keyboard_outlined,
      title: context.l10n.text('Keyboard'),
      children: [
        const SizedBox(height: 8),
        if (_matchesSearch('Keyboard', 'Vi key bindings'))
          ListTile(
            key: const Key('settings-vi-mode'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.keyboard_tab),
            title: Text(context.l10n.text('Vi key bindings')),
            trailing: Switch(
              value: settings.viModeEnabled,
              onChanged: settings.setViModeEnabled,
            ),
            onTap: () => settings.setViModeEnabled(!settings.viModeEnabled),
          ),
        for (final action in ViAction.values)
          if (_matchesSearch('Keyboard', action.label))
            _viBindingRow(settings, action),
        if (_matchesSearch('Keyboard', 'Reset to defaults'))
          ListTile(
            key: const Key('settings-vi-reset'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: Text(context.l10n.text('Reset to defaults')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => settings.resetViBindings(),
          ),
      ],
    );

    final accountSettings = _desktopSettingsCard(
      icon: Icons.account_balance_wallet_outlined,
      title: context.l10n.text('Accounts'),
      children: [
        if (_matchesSearch('Accounts', 'Manage accounts'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts),
            title: Text(context.l10n.text('Manage accounts')),
            subtitle: Text(accounts.activeAccount),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              adaptivePageRoute(context, builder: (_) => const AccountsPage()),
            ),
          ),
        if (_matchesSearch('Accounts', 'Currencies'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.currency_exchange),
            title: Text(context.l10n.text('Currencies')),
            subtitle: Text(settings.visibleCurrencies.join(', ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCurrencyPicker(context, settings),
          ),
        if (_matchesSearch('Accounts', 'Interactive Brokers'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance),
            title: Text(context.l10n.text('Interactive Brokers')),
            subtitle: Text(
              ibkrConfig.enabled
                  ? context.l10n.text('IBKR portfolio source • {url}', {
                      'url': ibkrConfig.baseUrl,
                    })
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
            if (_matchesSearch('Data', 'Export database'))
              OutlinedButton.icon(
                onPressed: () => _exportBackup(context),
                icon: const Icon(Icons.download),
                label: Text(context.l10n.text('Export database')),
              ),
            if (_matchesSearch('Data', 'Import database'))
              OutlinedButton.icon(
                onPressed: () => _importDatabase(context),
                icon: const Icon(Icons.upload),
                label: Text(context.l10n.text('Import database')),
              ),
            if (_matchesSearch('Data', 'Import CSV'))
              OutlinedButton.icon(
                onPressed: () => _importCsv(context),
                icon: const Icon(Icons.table_chart),
                label: Text(context.l10n.text('Import CSV')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_matchesSearch('Data', 'Sync'))
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
      ],
    );

    final danger = _desktopSettingsCard(
      icon: Icons.warning_amber_outlined,
      title: context.l10n.text('Danger zone'),
      children: [
        if (_matchesSearch('Danger zone', 'Delete all data'))
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
              final profileId = await profileDataRepository.profileIdForName(
                accounts.activeAccount,
              );
              await profileDataRepository.clearTrades(profileId);
              await marketDataDatabase.delete(marketDataDatabase.candles).go();
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
        if (_matchesSearch('About', 'What\'s New'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.new_releases_outlined),
            title: Text(context.l10n.text("What's New")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              adaptivePageRoute(context, builder: (_) => const WhatsNew()),
            ),
          ),
        if (_matchesSearch('About', 'Version'))
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
              await launchUrlString(url);
            },
          ),
        if (_matchesSearch('About', 'Author'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: Text(context.l10n.text('Author')),
            subtitle: const Text('Brandon Dick'),
            onTap: () async {
              const url = 'https://github.com/brandonp2412';
              await launchUrlString(url);
            },
          ),
        if (_matchesSearch('About', 'Source code'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: Text(context.l10n.text('Source code')),
            subtitle: Text(context.l10n.text('Check it out on GitHub')),
            onTap: () async {
              const url = 'https://github.com/brandonp2412/MarketMonk';
              await launchUrlString(url);
            },
          ),
      ],
    );

    final cards = [
      if (_hasMatches('General', _desktopSearchOptions['General']!)) general,
      if (_hasMatches('Appearance', _desktopSearchOptions['Appearance']!))
        appearance,
      if (_hasMatches('Accounts', _desktopSearchOptions['Accounts']!))
        accountSettings,
      if (_hasMatches('Charts', _desktopSearchOptions['Charts']!)) charts,
      if (_hasMatches('Keyboard', _desktopSearchOptions['Keyboard']!)) keyboard,
      if (_hasMatches('Data', _desktopSearchOptions['Data']!)) data,
      if (_hasMatches('Danger zone', _desktopSearchOptions['Danger zone']!))
        danger,
      if (_hasMatches('About', _desktopSearchOptions['About']!)) about,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = _searchQuery.isEmpty && constraints.maxWidth >= 920;
        final content = twoColumns
            ? Row(
                key: const Key('desktop-settings-two-column'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < cards.length;
                            index += 2) ...[
                          if (index > 0) const SizedBox(height: 16),
                          cards[index],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        for (var index = 1;
                            index < cards.length;
                            index += 2) ...[
                          if (index > 1) const SizedBox(height: 16),
                          cards[index],
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
              constraints: const BoxConstraints(
                maxWidth: _desktopContentMaxWidth,
              ),
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

    final appBar = AppBar(
      leading: widget.onClose == null
          ? null
          : IconButton(
              onPressed: widget.onClose,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
            ),
      title: Text(context.l10n.text('Settings')),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _searchField(),
      ),
    );

    if (isDesktopLayout(context)) {
      return Scaffold(
        appBar: appBar,
        body: _hasAnyMatches(_desktopSearchOptions)
            ? _buildDesktopSettings(settings, packageInfo)
            : _noSearchResults(),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: ListView(
        children: [
          if (!_hasAnyMatches(_mobileSearchOptions))
            Padding(
              padding: const EdgeInsets.all(24),
              child: _noSearchResults(),
            ),
          if (_hasMatches('General', _mobileSearchOptions['General']!))
            _sectionHeader(context.l10n.text('General')),
          if (_matchesSearch('General', 'Language')) ...[
            _languageDropdown(settings),
            const SizedBox(height: 8),
          ],
          if (_matchesSearch('General', 'Start page')) ...[
            _startPageDropdown(settings),
            const SizedBox(height: 8),
          ],
          if (_matchesSearch('General', 'Date format'))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Tooltip(
                message: context.l10n.text(
                  'How dates are displayed below graphs',
                ),
                child: DropdownButtonFormField<String>(
                  initialValue: settings.dateFormat,
                  items: _dateFormatOptions
                      .map(
                        (format) => DropdownMenuItem(
                          value: format,
                          child: Text(format),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      settings.setDateFormat(value ?? 'd/M/yy'),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Date format ({example})', {
                      'example': DateFormat(settings.dateFormat)
                          .format(DateTime.now()),
                    }),
                  ),
                ),
              ),
            ),
          if (_matchesSearch('General', 'Hide dollar amounts'))
            ListTile(
              leading: Icon(
                settings.hideDollarAmounts
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              title: Text(context.l10n.text('Hide dollar amounts')),
              trailing: Switch(
                value: settings.hideDollarAmounts,
                onChanged: settings.setHideDollarAmounts,
              ),
              onTap: () =>
                  settings.setHideDollarAmounts(!settings.hideDollarAmounts),
            ),
          if (_hasMatches('Appearance', _mobileSearchOptions['Appearance']!))
            _sectionHeader(context.l10n.text('Appearance')),
          if (_matchesSearch('Appearance', 'Theme'))
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
          if (_matchesSearch('Appearance', 'System color scheme'))
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
          if (_matchesSearch('Appearance', 'Pure black (AMOLED)'))
            ListTile(
              title: Text(context.l10n.text('Pure black (AMOLED)')),
              leading: const Icon(Icons.contrast),
              subtitle: Text(
                context.l10n.text('Use pure black for AMOLED displays'),
              ),
              trailing: Switch(
                value: settings.pureBlack,
                onChanged: (value) => settings.setPureBlack(value),
              ),
              onTap: () => settings.setPureBlack(!settings.pureBlack),
            ),
          if (!settings.systemColors &&
              _matchesSearch('Appearance', 'System color scheme'))
            _ColorPicker(settings: settings),
          if (_hasMatches('Charts', _mobileSearchOptions['Charts']!))
            _sectionHeader(context.l10n.text('Charts')),
          if (_matchesSearch('Charts', 'Rolling average'))
            ListTile(
              key: const Key('settings-rolling-average'),
              leading: const Icon(Icons.show_chart),
              title: Text(context.l10n.text('Rolling average')),
              trailing: Switch(
                value: settings.showRollingAverage,
                onChanged: settings.setShowRollingAverage,
              ),
              onTap: () =>
                  settings.setShowRollingAverage(!settings.showRollingAverage),
            ),
          if (_matchesSearch('Charts', 'Candles'))
            ListTile(
              key: const Key('settings-candlestick-chart'),
              leading: const Icon(Icons.candlestick_chart_outlined),
              title: const Text('Candles'),
              trailing: Switch(
                value: settings.showCandlesticks,
                onChanged: settings.setShowCandlesticks,
              ),
              onTap: () =>
                  settings.setShowCandlesticks(!settings.showCandlesticks),
            ),
          if (_matchesSearch('Charts', 'Chart gridlines'))
            _chartSwitch(
              label: 'Chart gridlines',
              icon: Icons.grid_on_outlined,
              value: settings.showChartGridlines,
              onChanged: settings.setShowChartGridlines,
            ),
          if (_matchesSearch('Charts', 'Chart shading'))
            _chartSwitch(
              label: 'Chart shading',
              icon: Icons.gradient_outlined,
              value: settings.fillChartArea,
              onChanged: settings.setFillChartArea,
            ),
          if (_matchesSearch('Charts', 'Curve line graphs'))
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
          if (_matchesSearch('Charts', 'Curve smoothness'))
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
                  divisions: 20,
                  inactiveColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.24),
                  onChanged: (value) {
                    runDetachedTask(
                      settings.setCurveSmoothness(value),
                      'Failed to save curve smoothness',
                    );
                  },
                ),
              ],
            ),
          if (_hasMatches('Charts', _mobileSearchOptions['Charts']!))
            _chartPreview(
              settings,
              height: MediaQuery.of(context).size.height * 0.3,
            ),
          if (_hasMatches('Keyboard', _mobileSearchOptions['Keyboard']!))
            _sectionHeader(context.l10n.text('Keyboard')),
          if (_matchesSearch('Keyboard', 'Vi key bindings'))
            ListTile(
              key: const Key('settings-vi-mode'),
              leading: const Icon(Icons.keyboard_tab),
              title: Text(context.l10n.text('Vi key bindings')),
              trailing: Switch(
                value: settings.viModeEnabled,
                onChanged: settings.setViModeEnabled,
              ),
              onTap: () => settings.setViModeEnabled(!settings.viModeEnabled),
            ),
          for (final action in ViAction.values)
            if (_matchesSearch('Keyboard', action.label))
              _viBindingRow(settings, action),
          if (_matchesSearch('Keyboard', 'Reset to defaults'))
            ListTile(
              key: const Key('settings-vi-reset'),
              leading: const Icon(Icons.restart_alt),
              title: Text(context.l10n.text('Reset to defaults')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => settings.resetViBindings(),
            ),
          if (_hasMatches('Accounts', _mobileSearchOptions['Accounts']!))
            _sectionHeader(context.l10n.text('Accounts')),
          if (_matchesSearch('Accounts', 'Manage accounts'))
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: Text(context.l10n.text('Manage accounts')),
              subtitle: Text(context.watch<AccountManager>().activeAccount),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                adaptivePageRoute(
                  context,
                  builder: (_) => const AccountsPage(),
                ),
              ),
            ),
          if (_matchesSearch('Accounts', 'Currencies'))
            ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: Text(context.l10n.text('Currencies')),
              subtitle: Text(settings.visibleCurrencies.join(', ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showCurrencyPicker(context, settings),
            ),
          if (_matchesSearch('Accounts', 'Interactive Brokers'))
            Builder(
              builder: (context) {
                final accounts = context.watch<AccountManager>();
                final config = accounts.ibkrConfigFor();
                return ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: Text(context.l10n.text('Interactive Brokers')),
                  subtitle: Text(
                    config.enabled
                        ? context.l10n.text('IBKR portfolio source • {url}', {
                            'url': config.baseUrl,
                          })
                        : context.l10n.text(
                            'Use a self-hosted IBKR portfolio API',
                          ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showIbkrSettings(context),
                );
              },
            ),
          if (_hasMatches('Data', _mobileSearchOptions['Data']!))
            _sectionHeader(context.l10n.text('Data')),
          if (_matchesSearch('Data', 'Export database'))
            Tooltip(
              message: context.l10n.text(
                'Download a full backup of every profile',
              ),
              child: ListTile(
                leading: const Icon(Icons.download),
                title: Text(context.l10n.text('Export database')),
                onTap: () => _exportBackup(context),
              ),
            ),
          if (_matchesSearch('Data', 'Import database'))
            Tooltip(
              message: context.l10n.text('Import a .sqlite database'),
              child: ListTile(
                leading: const Icon(Icons.upload),
                title: Text(context.l10n.text('Import database')),
                onTap: () => _importDatabase(context),
              ),
            ),
          if (_matchesSearch('Data', 'Import CSV'))
            Tooltip(
              message: context.l10n.text(
                'Import holdings from a broker CSV export',
              ),
              child: ListTile(
                leading: const Icon(Icons.table_chart),
                title: Text(context.l10n.text('Import CSV')),
                onTap: () => _importCsv(context),
              ),
            ),
          if (_matchesSearch('Data', 'Sync'))
            ListTile(
              onTap: settings.syncInProgress
                  ? null
                  : () => _syncAllTickers(context),
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
          if (_hasMatches(
            'Danger zone',
            _mobileSearchOptions['Danger zone']!,
          )) ...[
            const SizedBox(height: 8),
            const Divider(),
            _sectionHeader(context.l10n.text('Danger zone')),
          ],
          if (_matchesSearch('Danger zone', 'Delete all data'))
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
                      .delete(marketDataDatabase.candles)
                      .go();
                  clearAllSyncCache();
                  if (!context.mounted) return;
                  toast(context, context.l10n.text('All data deleted'));
                },
              ),
            ),
          if ((Platform.isAndroid || Platform.isWindows) &&
              _hasMatches('About', _mobileSearchOptions['About']!)) ...[
            _sectionHeader(context.l10n.text('About')),
            if (_matchesSearch('About', 'What\'s New'))
              ListTile(
                leading: const Icon(Icons.new_releases_outlined),
                title: Text(context.l10n.text("What's New")),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  adaptivePageRoute(context, builder: (_) => const WhatsNew()),
                ),
              ),
            if (_matchesSearch('About', 'Version'))
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
                  await launchUrlString(url);
                },
              ),
            if (_matchesSearch('About', 'Author'))
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
                  await launchUrlString(url);
                },
              ),
            if (_matchesSearch('About', 'License'))
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
                  await launchUrlString(url);
                },
              ),
            if (_matchesSearch('About', 'Source code'))
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
                  await launchUrlString(url);
                },
              ),
            if (_matchesSearch('About', 'Donate'))
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
                  await launchUrlString(url);
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
          context.l10n.text('Interactive Brokers — {account}', {
            'account': widget.account,
          }),
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
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.text('Test')),
          ),
          FilledButton(
            onPressed: _checking ? null : _save,
            child: Text(context.l10n.text('Save')),
          ),
        ],
      );
}

Color? parseHexThemeColor(String input) {
  final hex = input.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}

class _ColorPicker extends StatefulWidget {
  static const _colors = [
    defaultSeedColor,
    Color(0xFF2B7A78),
    Color(0xFF6750A4),
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFD32F2F),
    Color(0xFFF57C00),
    Color(0xFF7B1FA2),
    Color(0xFF0097A7),
    Color(0xFF5D4037),
    Color(0xFF455A64),
  ];

  final SettingsState settings;

  const _ColorPicker({required this.settings});

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late final TextEditingController _hexController;
  late Color _lastSeedColor;
  String? _hexError;

  static String _hexFor(Color color) => color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();

  @override
  void initState() {
    super.initState();
    _lastSeedColor = widget.settings.seedColor;
    _hexController = TextEditingController(text: _hexFor(_lastSeedColor));
  }

  @override
  void didUpdateWidget(covariant _ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastSeedColor != widget.settings.seedColor) {
      _lastSeedColor = widget.settings.seedColor;
      _hexController.text = _hexFor(_lastSeedColor);
      _hexError = null;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHex() {
    final selected = parseHexThemeColor(_hexController.text);
    if (selected == null) {
      setState(() => _hexError = 'Enter a 6-digit hex color');
      return;
    }
    setState(() => _hexError = null);
    runDetachedTask(
      widget.settings.setSeedColor(selected),
      'Failed to save custom theme color',
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = widget.settings.seedColor;
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
            children: [
              for (final color in _ColorPicker._colors)
                InkWell(
                  onTap: () => widget.settings.setSeedColor(color),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selectedColor == color
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selectedColor == color
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              if (!_ColorPicker._colors.contains(selectedColor))
                Container(
                  key: const Key('settings-custom-color-preview'),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    Icons.check,
                    color: selectedColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ThemeColorWheel(
            color: selectedColor,
            onChanged: (color) => runDetachedTask(
              widget.settings.setSeedColor(color),
              'Failed to save theme color',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('settings-custom-color-hex'),
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 7,
              onSubmitted: (_) => _applyHex(),
              decoration: InputDecoration(
                labelText: 'Hex color',
                hintText: '#RRGGBB',
                errorText: _hexError,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const Key('settings-apply-custom-color'),
                  tooltip: 'Apply color',
                  onPressed: _applyHex,
                  icon: const Icon(Icons.check_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViRebindDialog extends StatefulWidget {
  const _ViRebindDialog({required this.settings, required this.action});

  final SettingsState settings;
  final ViAction action;

  @override
  State<_ViRebindDialog> createState() => _ViRebindDialogState();
}

class _ViRebindDialogState extends State<_ViRebindDialog> {
  String? _captured;
  bool _handlerInstalled = false;
  bool _reservedKey = false;

  bool _handleKeyEvent(KeyEvent event) {
    final label = viKeyLabelFromEvent(
      event,
      shiftPressed: ViKeyState.instance.shiftPressed,
      otherModifierPressed: ViKeyState.instance.controlPressed ||
          ViKeyState.instance.altPressed ||
          ViKeyState.instance.metaPressed,
    );
    if (label != null) {
      setState(() {
        _reservedKey = viReservedKeys.contains(label) || event.character == '?';
        _captured = _reservedKey ? null : label;
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    ViKeyState.instance.ensureInstalled();
    ViNavigation.instance.capturingBinding = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _handlerInstalled = true;
  }

  @override
  void dispose() {
    ViNavigation.instance.capturingBinding = false;
    if (_handlerInstalled) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        context.l10n.text('Bind {action}', {'action': widget.action.label}),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _reservedKey
                  ? 'That key is reserved for navigation or help'
                  : _captured == null
                      ? context.l10n.text('Press a key...')
                      : viKeyDisplayName(_captured!),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text(
                'Use a single letter, number, or symbol. '
                'Shift makes a letter uppercase. f, F, ?, comma and 1–3 are reserved.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('vi-rebind-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          key: const Key('vi-rebind-done'),
          onPressed: _captured == null
              ? null
              : () {
                  final label = _captured!;
                  Navigator.pop(context);
                  unawaited(widget.settings.setViBinding(widget.action, label));
                },
          child: Text(context.l10n.text('Done')),
        ),
      ],
    );
  }
}
