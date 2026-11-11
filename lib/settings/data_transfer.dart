part of '../settings_page.dart';

extension _SettingsDataTransfer on _SettingsPageState {
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
                ...(_SettingsPageState
                            ._brokerCsvInstructions[currentSelection.name] ??
                        [])
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
}
