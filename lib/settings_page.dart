import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/accounts_page.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/app.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/csv_import.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings/color_picker.dart';
import 'package:market_monk/settings/ibkr_settings_dialog.dart';
import 'package:market_monk/settings/vi_rebind_dialog.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:market_monk/whats_new.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

part 'settings/data_transfer.dart';
part 'settings/desktop_settings.dart';

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
          0,
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
      builder: (_) => IbkrSettingsDialog(
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
        builder: (_) => ViRebindDialog(settings: settings, action: action),
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
        padding: const EdgeInsets.only(bottom: bottomNavScrollClearance),
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
            SettingsColorPicker(settings: settings),
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
                      switch (true) {
                        _ when settings.syncTotal == 0 =>
                          context.l10n.text('No sync running'),
                        _ when settings.syncFailed == 0 => context.l10n.text(
                            'Last sync completed {completed}/{total}',
                            {
                              'completed': settings.syncCompleted,
                              'total': settings.syncTotal,
                            },
                          ),
                        _ => context.l10n.text(
                            'Last sync completed with {failed} failed',
                            {'failed': settings.syncFailed},
                          ),
                      },
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
