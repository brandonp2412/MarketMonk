import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/vi_keys.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:provider/provider.dart';

const viHintAlphabet = 'qwerasdfzcv';

List<String> viHintLabels(int count) {
  var width = 1;
  var capacity = viHintAlphabet.length;
  while (capacity < count) {
    width++;
    capacity *= viHintAlphabet.length;
  }
  return List.generate(count, (index) {
    var value = index;
    var label = '';
    for (var i = 0; i < width; i++) {
      label = viHintAlphabet[value % viHintAlphabet.length] + label;
      value ~/= viHintAlphabet.length;
    }
    return label;
  });
}

class _Hint {
  const _Hint(this.rect, this.activate);
  final Rect rect;
  final VoidCallback activate;
}

class ViOverlay extends StatefulWidget {
  const ViOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<ViOverlay> createState() => _ViOverlayState();
}

class _ViOverlayState extends State<ViOverlay> {
  final _contentKey = GlobalKey();
  List<_Hint>? _hints;
  String _prefix = '';
  bool _help = false;
  Rect? _focusRect;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    ViNavigation.instance.focusedContext.addListener(_updateFocus);
    FocusManager.instance.addListener(_updateFocus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    ViNavigation.instance.focusedContext.removeListener(_updateFocus);
    FocusManager.instance.removeListener(_updateFocus);
    ViNavigation.instance.overlayActive = false;
    super.dispose();
  }

  void _updateFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      final focus = ViNavigation.instance.focusedContext.value ??
          (primary is FocusScopeNode ? null : primary?.context);
      final root = context.findRenderObject();
      final render = focus?.mounted == true ? focus!.findRenderObject() : null;
      Rect? rect;
      if (root is RenderBox &&
          render is RenderBox &&
          render.attached &&
          render.hasSize) {
        rect = (render.localToGlobal(Offset.zero) -
                root.localToGlobal(Offset.zero)) &
            render.size;
      }
      setState(() => _focusRect = rect);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _close() => setState(() {
        ViNavigation.instance.overlayActive = false;
        _hints = null;
        _prefix = '';
        _help = false;
      });

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !mounted ||
        ViNavigation.instance.capturingBinding) return false;
    if (!context.read<SettingsState>().viModeEnabled) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_hints != null || _help) {
        _close();
        return true;
      }
      final focus = FocusManager.instance.primaryFocus?.context;
      final editing = focus?.widget is EditableText ||
          focus?.findAncestorWidgetOfExactType<EditableText>() != null;
      FocusManager.instance.primaryFocus?.unfocus();
      if (!editing &&
          ModalRouteTracker.instance.modalDepth == 0 &&
          ViNavigation.instance.closeSettings?.call() == true) return true;
      return false;
    }
    if (_help) {
      ViNavigation.instance.consumedEvent = event;
      _close();
      return true;
    }
    if (_hints != null) {
      ViNavigation.instance.consumedEvent = event;
      final letter = event.character?.toLowerCase();
      if (letter == null || !viHintAlphabet.contains(letter)) return true;
      final prefix = _prefix + letter;
      final labels = viHintLabels(_hints!.length);
      final index = labels.indexOf(prefix);
      if (index >= 0) {
        final action = _hints![index].activate;
        _close();
        action();
      } else if (labels.any((label) => label.startsWith(prefix))) {
        setState(() => _prefix = prefix);
      } else {
        setState(() => _prefix = '');
      }
      return true;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null)
      return false;
    if (event.character == '?') {
      ViNavigation.instance.consumedEvent = event;
      ViNavigation.instance.overlayActive = true;
      setState(() => _help = true);
      return true;
    }
    if (event.character == 'f' || event.character == 'F') {
      ViNavigation.instance.consumedEvent = event;
      _showHints(secondary: event.character == 'F');
      return true;
    }
    return false;
  }

  void _showHints({bool secondary = false}) {
    final root = _contentKey.currentContext;
    final box = context.findRenderObject();
    if (root == null || box is! RenderBox) return;
    final origin = box.localToGlobal(Offset.zero);
    final bounds = Offset.zero & box.size;
    final hints = <_Hint>[];
    void visit(Element element, [bool generic = true]) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage)
        return;
      final widget = element.widget;
      VoidCallback? action;
      if (widget is Focus &&
          widget.onKeyEvent != null &&
          widget.focusNode != null) action = widget.focusNode!.requestFocus;
      if (widget is ButtonStyleButton) action = widget.onPressed;
      if (widget is IconButton) action = widget.onPressed;
      if (widget is ListTile) action = widget.onTap;
      if (generic && widget is InkResponse) action = widget.onTap;
      if (generic && widget is GestureDetector) action = widget.onTap;
      if (widget is EditableText) action = widget.focusNode.requestFocus;
      if (widget is Switch && widget.onChanged != null)
        action = () => widget.onChanged!(!widget.value);
      if (widget is Checkbox && widget.onChanged != null)
        action = () => widget.onChanged!(widget.value != true);
      if (widget is Slider && widget.onChanged != null) {
        action = () {
          void focusSlider(Element child) {
            if (child.widget is Focus &&
                (child.widget as Focus).focusNode != null) {
              (child.widget as Focus).focusNode!.requestFocus();
              return;
            }
            child.visitChildren(focusSlider);
          }

          element.visitChildren(focusSlider);
        };
      }
      if (secondary) {
        action = null;
        if (widget is InkResponse) action = widget.onLongPress;
        if (widget is ListTile) action = widget.onLongPress;
        if (widget is GestureDetector) {
          action = widget.onLongPress;
          if (widget.onSecondaryTapUp != null) {
            action = () {
              final render = element.findRenderObject();
              if (render is RenderBox && render.attached) {
                final local = render.size.center(Offset.zero);
                widget.onSecondaryTapUp!(
                  TapUpDetails(
                    globalPosition: render.localToGlobal(local),
                    localPosition: local,
                    kind: PointerDeviceKind.mouse,
                  ),
                );
              }
            };
          }
        }
      }
      final render = element.findRenderObject();
      if (action != null &&
          ModalRoute.of(element)?.isCurrent != false &&
          render is RenderBox &&
          render.hasSize &&
          render.attached) {
        final rect = (render.localToGlobal(Offset.zero) - origin) & render.size;
        if (rect.width > 0 && rect.height > 0 && bounds.contains(rect.center)) {
          hints.add(_Hint(rect, action));
          if (!secondary && widget is! Focus && widget is! ListTile) return;
          element.visitChildren((child) => visit(child, false));
          return;
        }
      }
      element.visitChildren((child) => visit(child, generic));
    }

    (root as Element).visitChildren(visit);
    ViNavigation.instance.overlayActive = true;
    setState(() {
      _hints = hints;
      _prefix = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final hints = settings.viModeEnabled ? _hints : null;
    final labels = viHintLabels(hints?.length ?? 0);
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(key: _contentKey, child: widget.child),
        if (settings.viModeEnabled &&
            _focusRect != null &&
            hints == null &&
            !_help)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            left: _focusRect!.left,
            top: _focusRect!.top,
            width: _focusRect!.width,
            height: _focusRect!.height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        if (hints != null) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
            ),
          ),
          for (var i = 0; i < hints.length; i++)
            if (labels[i].startsWith(_prefix))
              Positioned(
                left: hints[i]
                    .rect
                    .left
                    .clamp(0, MediaQuery.sizeOf(context).width - 40),
                top: hints[i]
                    .rect
                    .top
                    .clamp(0, MediaQuery.sizeOf(context).height - 28),
                child: Material(
                  elevation: 6,
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    onTap: () {
                      final action = hints[i].activate;
                      _close();
                      action();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        labels[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
        if (_help && settings.viModeEnabled)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 520, maxHeight: 650),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Keyboard controls',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          for (final entry in settings.viBindings.entries)
                            _helpRow(
                              viKeyDisplayName(entry.value),
                              entry.key.label,
                            ),
                          _helpRow(
                            'f',
                            'Show click hints; type the letters to activate',
                          ),
                          _helpRow(
                            'F',
                            'Show context-menu and long-press hints',
                          ),
                          _helpRow('?', 'Show this help'),
                          _helpRow(
                            '1 / 2 / 3',
                            'Charts / Portfolio / Holdings',
                          ),
                          _helpRow(',', 'Settings'),
                          _helpRow(
                            'Tab / Shift Tab',
                            'Next / previous control',
                          ),
                          _helpRow('Enter / Space', 'Activate focused control'),
                          _helpRow(
                            'Arrow keys',
                            'Adjust sliders, menus, charts and the color wheel',
                          ),
                          _helpRow(
                            'Home / End',
                            'First / last point on a line chart',
                          ),
                          _helpRow(
                            'Enter / r',
                            'On a line chart: mark range start/end / reset zoom',
                          ),
                          _helpRow(
                            'Escape',
                            'Cancel hints or leave text entry',
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _close,
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _helpRow(String key, String description) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                key,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(child: Text(description)),
          ],
        ),
      );
}
