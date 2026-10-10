import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/l10n/app_localizations.dart';

/// An existing app action offered by a secondary-click menu.
class DesktopMenuAction {
  /// A null callback keeps an unavailable action visible but disabled.
  const DesktopMenuAction(this.label, this.onSelected);

  /// Localized text shown in the popup.
  final String label;

  /// Invoked only after the user chooses this action.
  final VoidCallback? onSelected;
}

/// Adds a pointer-positioned menu without changing primary-click behavior.
class DesktopContextMenu extends StatelessWidget {
  /// Wraps an item or page with its available desktop actions.
  const DesktopContextMenu({
    super.key,
    required this.actions,
    required this.child,
    this.copyText,
  });

  /// Offers the tile's existing action using its displayed text as the label.
  factory DesktopContextMenu.listTile({required ListTile child}) {
    final title = child.title;
    return DesktopContextMenu(
      actions: [
        if (title is Text && title.data != null)
          DesktopMenuAction(title.data!, child.onTap),
      ],
      child: child,
    );
  }

  /// Actions for the wrapped item, in display order.
  final List<DesktopMenuAction> actions;

  /// Content retaining its original touch and primary-click behavior.
  final Widget child;

  /// When present, adds a Copy action for this text.
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform != TargetPlatform.linux &&
        platform != TargetPlatform.macOS &&
        platform != TargetPlatform.windows) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) async {
        final entries = [
          ...actions,
          if (copyText != null)
            DesktopMenuAction(context.l10n.text('Copy'), () {
              unawaited(Clipboard.setData(ClipboardData(text: copyText!)));
            }),
        ];
        if (entries.isEmpty) return;
        final overlay =
            Overlay.of(context).context.findRenderObject()! as RenderBox;
        final position = overlay.globalToLocal(details.globalPosition);
        final selected = await showMenu<int>(
          context: context,
          position: RelativeRect.fromRect(
            position & const Size(1, 1),
            Offset.zero & overlay.size,
          ),
          items: [
            for (var i = 0; i < entries.length; i++)
              PopupMenuItem(
                value: i,
                enabled: entries[i].onSelected != null,
                child: Text(entries[i].label),
              ),
          ],
        );
        if (selected != null && context.mounted) {
          entries[selected].onSelected?.call();
        }
      },
      child: child,
    );
  }
}
