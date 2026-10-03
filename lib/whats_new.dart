import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/utils.dart';

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
  static const _pageSize = 10;
  List<_Changelog> _changelogs = [];
  List<String> _changelogFiles = [];
  int _page = 0;
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    runDetachedTask(_loadChangelogs(), 'Failed to load changelog');
  }

  Future<void> _loadChangelogs() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files = manifest
          .listAssets()
          .where(
            (key) =>
                key.startsWith('assets/changelogs/') && key.endsWith('.txt'),
          )
          .toList();

      files.sort((firstPath, secondPath) {
        final firstTimestamp =
            int.tryParse(firstPath.split('/').last.split('.').first) ?? 0;
        final secondTimestamp =
            int.tryParse(secondPath.split('/').last.split('.').first) ?? 0;
        return secondTimestamp.compareTo(firstTimestamp);
      });

      if (!mounted) return;
      setState(() {
        _changelogFiles = files;
        _page = 0;
      });
      await _loadPage(0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadPage(int page) async {
    final pageFiles = _changelogFiles.skip(page * _pageSize).take(_pageSize);
    final result = <_Changelog>[];
    for (final path in pageFiles) {
      final changelog = await _loadChangelogFile(path);
      if (changelog != null) result.add(changelog);
    }
    if (!mounted || _page != page) return;
    setState(() {
      _changelogs = result;
      _isLoading = false;
    });
  }

  Future<void> _setPage(int page) async {
    final pageCount = (_changelogFiles.length / _pageSize).ceil();
    if (page < 0 || page >= pageCount) return;
    setState(() {
      _page = page;
      _isLoading = true;
    });
    await _loadPage(page);
  }

  Future<_Changelog?> _loadChangelogFile(String path) async {
    try {
      final content = await rootBundle.loadString(path);
      if (content.trim().isEmpty) return null;

      final filename = path.split('/').last.replaceAll('.txt', '');
      final timestamp = int.tryParse(filename);
      if (timestamp == null) return null;

      return _Changelog(
        created: DateFormat.yMMMd().format(
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
        ),
        content: content.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Text(context.l10n.text('Unable to load release notes.')),
      );
    }
    if (_changelogs.isEmpty) {
      return AppEmptyState(
        icon: Icons.newspaper_rounded,
        title: context.l10n.text('No release notes available'),
        message: context.l10n.text('There is nothing new to show yet.'),
      );
    }

    final pageCount = (_changelogFiles.length / _pageSize).ceil();
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
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
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 0 ? () => _setPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous page',
              ),
              Text('${_page + 1} / $pageCount'),
              IconButton(
                onPressed:
                    _page + 1 < pageCount ? () => _setPage(_page + 1) : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next page',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text("What's New"))),
      body: _buildBody(),
    );
  }
}
