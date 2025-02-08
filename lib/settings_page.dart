import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:path/path.dart' as p;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
                final dbFolder = await getApplicationDocumentsDirectory();
                await db.close();
                await sourceFile
                    .copy(p.join(dbFolder.path, 'market-monk.sqlite'));
                db = Database();
                if (!context.mounted) return;
                final settingsState = context.read<SettingsState>();
                await settingsState.init();
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
