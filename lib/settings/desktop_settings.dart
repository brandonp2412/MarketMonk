part of '../settings_page.dart';

extension _DesktopSettingsView on _SettingsPageState {
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
          SettingsColorPicker(settings: settings),
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
        if (_hasMatches(
          'Charts',
          _SettingsPageState._desktopSearchOptions['Charts']!,
        ))
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
              switch (true) {
                _ when settings.syncInProgress => context.l10n.text(
                    'Syncing {symbol} ({completed}/{total})',
                    {
                      'symbol': settings.syncingSymbol ?? '',
                      'completed': settings.syncCompleted,
                      'total': settings.syncTotal,
                    },
                  ),
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
      if (_hasMatches(
        'General',
        _SettingsPageState._desktopSearchOptions['General']!,
      ))
        general,
      if (_hasMatches(
        'Appearance',
        _SettingsPageState._desktopSearchOptions['Appearance']!,
      ))
        appearance,
      if (_hasMatches(
        'Accounts',
        _SettingsPageState._desktopSearchOptions['Accounts']!,
      ))
        accountSettings,
      if (_hasMatches(
        'Charts',
        _SettingsPageState._desktopSearchOptions['Charts']!,
      ))
        charts,
      if (_hasMatches(
        'Keyboard',
        _SettingsPageState._desktopSearchOptions['Keyboard']!,
      ))
        keyboard,
      if (_hasMatches(
        'Data',
        _SettingsPageState._desktopSearchOptions['Data']!,
      ))
        data,
      if (_hasMatches(
        'Danger zone',
        _SettingsPageState._desktopSearchOptions['Danger zone']!,
      ))
        danger,
      if (_hasMatches(
        'About',
        _SettingsPageState._desktopSearchOptions['About']!,
      ))
        about,
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
                maxWidth: _SettingsPageState._desktopContentMaxWidth,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }
}
