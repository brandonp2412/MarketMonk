import 'package:flutter/material.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/main.dart';
import 'package:provider/provider.dart';

class ProfilePicker extends StatelessWidget {
  final VoidCallback? onExport;
  final VoidCallback? onShare;

  const ProfilePicker({super.key, this.onExport, this.onShare});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountManager>();
    final theme = Theme.of(context);
    final activeProfile = accounts.activeAccount;
    final name = activeProfile.trim();
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Switch profile: $activeProfile',
      onSelected: (value) {
        if (value == '__export__') {
          onExport?.call();
        } else if (value == '__share__') {
          onShare?.call();
        } else if (value != activeProfile) {
          runDetachedTask(
            accounts.switchAccount(value),
            'Failed to switch account',
          );
        }
      },
      itemBuilder: (_) => [
        for (final profile in accounts.accounts)
          CheckedPopupMenuItem<String>(
            value: profile,
            checked: profile == activeProfile,
            child: Text(profile),
          ),
        if (onExport != null || onShare != null) const PopupMenuDivider(),
        if (onExport != null)
          PopupMenuItem<String>(
            value: '__export__',
            child: Row(
              children: [
                const Icon(Icons.download_rounded, size: 20),
                const SizedBox(width: 8),
                Text(context.l10n.text('Export CSV')),
              ],
            ),
          ),
        if (onShare != null)
          PopupMenuItem<String>(
            value: '__share__',
            child: Row(
              children: [
                const Icon(Icons.share_rounded, size: 20),
                const SizedBox(width: 8),
                Text(context.l10n.text('Share CSV')),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            Align(
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      Color.lerp(
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary,
                        0.25,
                      )!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
