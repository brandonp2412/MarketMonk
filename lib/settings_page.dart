import 'dart:io';

import 'package:flutter/material.dart';
import 'package:market_monk/settings_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
          if (Platform.isAndroid || Platform.isWindows) ...[
            const SizedBox(height: 16),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8),
              child: Text("About",
                  style: Theme.of(context).textTheme.headlineLarge),
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
