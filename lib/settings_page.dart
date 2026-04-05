import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/csv_import.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _importCsv(BuildContext context) async {
    // Step 1: broker selection dialog
    BrokerCsvParser? selectedParser;
    BrokerCsvParser currentSelection = supportedBrokers.first;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select broker'),
          content: DropdownButton<BrokerCsvParser>(
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                selectedParser = currentSelection;
                Navigator.pop(context);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (selectedParser == null || !context.mounted) return;

    // Step 2: pick the CSV file
    final result = await FilePicker.platform.pickFiles();
    if (result == null || !context.mounted) return;

    // Step 3: parse
    ParseResult parsed;
    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      parsed = selectedParser!.parse(content);
    } catch (e) {
      if (!context.mounted) return;
      toast(context, 'Failed to parse CSV: $e');
      return;
    }

    if (parsed.holdings.isEmpty && parsed.trades.isEmpty) {
      if (!context.mounted) return;
      toast(context, 'No data found in the selected file');
      return;
    }

    // Step 4: preview dialog
    bool confirmed = false;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Import ${parsed.holdings.length} holdings'
          '${parsed.trades.isNotEmpty ? ' & ${parsed.trades.length} trades' : ''}',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (parsed.holdings.isNotEmpty) ...[
                const ListTile(
                  dense: true,
                  title: Text(
                    'Holdings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...parsed.holdings.map(
                  (h) => ListTile(
                    dense: true,
                    title: Text(h.symbol),
                    subtitle: Text(h.name),
                    trailing: Text(
                      '${h.amount.toStringAsFixed(2)} @ \$${h.purchasePrice.toStringAsFixed(2)}',
                    ),
                  ),
                ),
              ],
              if (parsed.trades.isNotEmpty) ...[
                const ListTile(
                  dense: true,
                  title: Text(
                    'Trades',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...parsed.trades.take(10).map(
                  (t) => ListTile(
                    dense: true,
                    title: Text('${t.symbol} — ${t.tradeType.toUpperCase()}'),
                    subtitle: Text(t.tradeDate.toIso8601String().substring(0, 10)),
                    trailing: Text(
                      '${t.quantity.abs().toStringAsFixed(2)} @ \$${t.price.toStringAsFixed(2)}',
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              confirmed = true;
              Navigator.pop(context);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (!confirmed || !context.mounted) return;

    // Step 5: insert into DB
    final holdingsCount = await importHoldings(parsed.holdings);
    final tradesCount = await importTrades(parsed.trades);
    if (!context.mounted) return;
    toast(
      context,
      'Imported $holdingsCount holdings and $tradesCount trades',
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = PackageInfo.fromPlatform();
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonFormField<ThemeMode>(
              value: settings.theme,
              decoration: const InputDecoration(
                labelStyle: TextStyle(),
                labelText: 'Theme',
              ),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text("System"),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text("Dark"),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text("Light"),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                final settings = context.read<SettingsState>();
                settings.setTheme(value);
                final prefs = await SharedPreferences.getInstance();
                prefs.setString('theme', value.toString());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Tooltip(
              message: 'How dates are displayed below graphs',
              child: DropdownButtonFormField<String>(
                value: settings.dateFormat,
                items: const [
                  DropdownMenuItem(value: "d/M/yy", child: Text("d/M/yy")),
                  DropdownMenuItem(value: "M/d/yy", child: Text("M/d/yy")),
                  DropdownMenuItem(value: "d-M-yy", child: Text("d-M-yy")),
                  DropdownMenuItem(value: "M-d-yy", child: Text("M-d-yy")),
                  DropdownMenuItem(value: "d.M.yy", child: Text("d.M.yy")),
                  DropdownMenuItem(value: "M.d.yy", child: Text("M.d.yy")),
                ],
                onChanged: (value) => settings.setDateFormat(value ?? 'd/M/yy'),
                decoration: InputDecoration(
                  labelText:
                      'Date format (${DateFormat(settings.dateFormat).format(DateTime.now())})',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Tooltip(
              message: 'Use the primary color of your device for the app',
              child: ListTile(
                title: const Text('System color scheme'),
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
          ),
          if (!settings.systemColors) _ColorPicker(settings: settings),
          Tooltip(
            message: 'Use wavy curves in the graphs page',
            child: ListTile(
              title: const Text('Curve line graphs'),
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
                  "Curve smoothness",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Slider(
                value: settings.curveSmoothness,
                inactiveColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.24),
                onChanged: (value) {
                  settings.setCurveSmoothness(value);
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
          const SizedBox(height: 8),
          Tooltip(
            message: 'Download the database file for the entire app',
            child: ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Export database'),
              onTap: () async {
                Navigator.pop(context);
                final dbFolder = await getApplicationSupportDirectory();
                final file = File(p.join(dbFolder.path, 'market-monk.sqlite'));
                final bytes = await file.readAsBytes();
                final result = await FilePicker.platform.saveFile(
                  fileName: 'market-monk.sqlite',
                  bytes: bytes,
                );
                if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                  await file.copy(result!);
              },
            ),
          ),
          Tooltip(
            message: 'Import holdings from a broker CSV export',
            child: ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Import CSV'),
              onTap: () => _importCsv(context),
            ),
          ),
          Tooltip(
            message: 'Import a .sqlite database',
            child: ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Import database'),
              onTap: () async {
                Navigator.pop(context);
                FilePickerResult? result =
                    await FilePicker.platform.pickFiles();
                if (result == null) return;

                File sourceFile = File(result.files.single.path!);

                // Validate SQLite magic header before overwriting the database.
                // SQLite files start with "SQLite format 3\0" (16 bytes).
                final raf = await sourceFile.open();
                final header = await raf.read(16);
                await raf.close();
                const sqliteMagic = [
                  0x53,
                  0x51,
                  0x4C,
                  0x69,
                  0x74,
                  0x65,
                  0x20,
                  0x66,
                  0x6F,
                  0x72,
                  0x6D,
                  0x61,
                  0x74,
                  0x20,
                  0x33,
                  0x00,
                ];
                final isValid = header.length == 16 &&
                    List.generate(16, (i) => header[i] == sqliteMagic[i])
                        .every((b) => b);
                if (!isValid) {
                  if (!context.mounted) return;
                  toast(context, 'Selected file is not a valid database');
                  return;
                }

                final dbFolder = await getApplicationSupportDirectory();
                await db.close();
                await sourceFile
                    .copy(p.join(dbFolder.path, 'market-monk.sqlite'));
                db = Database();
                if (!context.mounted) return;
                Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
              },
            ),
          ),
          if (Platform.isAndroid || Platform.isWindows) ...[
            const SizedBox(height: 16),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8),
              child: Text(
                "About",
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("Version"),
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
              title: const Text("Author"),
              leading: const Icon(Icons.person),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) => const Text("Brandon Presley"),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url = 'https://github.com/brandonp2412';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: const Text("License"),
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
              title: const Text("Source code"),
              leading: const Icon(Icons.code),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) =>
                    const Text("Check it out on GitHub"),
              ),
              onTap: () async {
                if (Platform.isIOS || Platform.isMacOS) return;
                const url = 'https://github.com/brandonp2412/MarketMonk';
                if (await canLaunchUrlString(url)) await launchUrlString(url);
              },
            ),
            ListTile(
              title: const Text("Donate"),
              leading: const Icon(Icons.favorite_outline),
              subtitle: FutureBuilder(
                future: packageInfo,
                builder: (context, snapshot) =>
                    const Text("Help support this project"),
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
          Text('App color', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colors.map((color) {
              final isSelected = settings.seedColor.toARGB32() == color.toARGB32();
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
