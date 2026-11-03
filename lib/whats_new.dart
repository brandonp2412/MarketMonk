import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/update_notice.dart';
import 'package:market_monk/utils.dart';
import 'package:url_launcher/url_launcher_string.dart';

class WhatsNew extends StatefulWidget {
  const WhatsNew({super.key});

  @override
  State<WhatsNew> createState() => _WhatsNewState();
}

class _ReleaseNote {
  final String version;
  final String date;
  final String sourceUrl;
  final List<String> changes;

  const _ReleaseNote({
    required this.version,
    required this.date,
    required this.sourceUrl,
    required this.changes,
  });

  factory _ReleaseNote.fromJson(Map<String, dynamic> json) => _ReleaseNote(
        version: json['version'] as String,
        date: json['date'] as String,
        sourceUrl: json['sourceUrl'] as String,
        changes: (json['changes'] as List<dynamic>).cast<String>(),
      );
}

class _WhatsNewState extends State<WhatsNew> {
  static const _pageSize = 10;
  static const _previewChanges = 5;
  List<_ReleaseNote> _releases = [];
  final Set<String> _expandedVersions = {};
  int _visibleCount = _pageSize;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _showUpdateNotices = true;

  @override
  void initState() {
    super.initState();
    runDetachedTask(_loadHistory(), 'Failed to load changelog');
    runDetachedTask(
      _loadUpdateNoticePreference(),
      'Failed to load update preference',
    );
  }

  Future<void> _loadUpdateNoticePreference() async {
    final prefs = await SqliteSettings.getInstance();
    if (mounted) {
      setState(() {
        _showUpdateNotices = prefs.getBool(showUpdateNoticesKey) ?? true;
      });
    }
  }

  Future<void> _setUpdateNotices(bool enabled) async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool(showUpdateNoticesKey, enabled);
    if (mounted) setState(() => _showUpdateNotices = enabled);
  }

  Future<void> _loadHistory() async {
    try {
      final data = jsonDecode(
        await rootBundle.loadString('assets/release_history.json'),
      ) as List<dynamic>;
      final releases = data
          .map((entry) => _ReleaseNote.fromJson(entry as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Widget _buildRelease(_ReleaseNote release) {
    final expanded = _expandedVersions.contains(release.version);
    final changes =
        expanded ? release.changes : release.changes.take(_previewChanges);
    final hasHiddenChanges = release.changes.length > _previewChanges;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              release.version,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat.yMMMd().format(
                                DateTime.parse(release.date),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await launchUrlString(release.sourceUrl);
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Source'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (release.changes.isEmpty)
                    const Text('No separate changes recorded for this release.')
                  else
                    for (final change in changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6, right: 10),
                              child: Icon(Icons.circle, size: 6),
                            ),
                            Expanded(child: Text(change)),
                          ],
                        ),
                      ),
                  if (hasHiddenChanges)
                    TextButton(
                      onPressed: () => setState(() {
                        if (expanded) {
                          _expandedVersions.remove(release.version);
                        } else {
                          _expandedVersions.add(release.version);
                        }
                      }),
                      child: Text(
                        expanded
                            ? 'Show fewer changes'
                            : 'Show all ${release.changes.length} changes',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const SizedBox.expand();
    if (_loadFailed) {
      return Center(
        child: Text(context.l10n.text('Unable to load release notes.')),
      );
    }
    if (_releases.isEmpty) {
      return AppEmptyState(
        icon: Icons.newspaper_rounded,
        title: context.l10n.text('No release notes available'),
        message: context.l10n.text('There is nothing new to show yet.'),
      );
    }

    final visibleCount = _visibleCount.clamp(0, _releases.length);
    final hasMore = visibleCount < _releases.length;
    return ListView.builder(
      key: const PageStorageKey('whats-new-history'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: visibleCount + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < visibleCount) return _buildRelease(_releases[index]);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('Showing $visibleCount of ${_releases.length} releases'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('load-more-releases'),
                  onPressed: () => setState(() {
                    _visibleCount += _pageSize;
                  }),
                  icon: const Icon(Icons.expand_more),
                  label: Text(context.l10n.text('Load more')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text("What's New"))),
      body: Column(
        children: [
          SwitchListTile.adaptive(
            title: Text(context.l10n.text('Show update notices')),
            value: _showUpdateNotices,
            onChanged: _setUpdateNotices,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}
