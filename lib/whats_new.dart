import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class WhatsNew extends StatefulWidget {
  const WhatsNew({super.key});

  @override
  State<WhatsNew> createState() => _WhatsNewState();
}

class _Changelog {
  final String created;
  final String content;

  _Changelog({required this.created, required this.content});
}

class _WhatsNewState extends State<WhatsNew> {
  List<_Changelog> _changelogs = [];

  @override
  void initState() {
    super.initState();
    _loadChangelogs();
  }

  Future<void> _loadChangelogs() async {
    final manifest = await AssetManifest.loadFromAssetBundle(
      DefaultAssetBundle.of(context),
    );
    final files = manifest
        .listAssets()
        .where((key) => key.startsWith('assets/changelogs/'))
        .toList();

    files.sort((a, b) {
      final aNum = int.tryParse(a.split('/').last.split('.').first) ?? 0;
      final bNum = int.tryParse(b.split('/').last.split('.').first) ?? 0;
      return bNum.compareTo(aNum);
    });

    final result = <_Changelog>[];
    for (final path in files) {
      try {
        final content = await rootBundle.loadString(path);
        if (content.trim().isEmpty) continue;
        final filename = path.split('/').last.replaceAll('.txt', '');
        final timestamp = int.tryParse(filename);
        if (timestamp == null) continue;
        result.add(
          _Changelog(
            created: DateFormat.yMMMd().format(
              DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
            ),
            content: content.trim(),
          ),
        );
      } catch (_) {}
    }

    if (mounted) setState(() => _changelogs = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("What's New")),
      body: _changelogs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _changelogs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = _changelogs[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.created,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(log.content),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
