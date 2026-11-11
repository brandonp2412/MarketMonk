part of '../market_line_chart.dart';

class _MarketLineChartInteraction extends StatefulWidget {
  final _MarketLineChartRenderer renderer;
  final String Function(PlotMark mark) rowLabel;
  final String Function(int index)? candleTooltipTitle;
  final List<String> Function(int index)? candleTooltipRows;
  final bool stickyTooltip;
  final ValueNotifier<int?>? externalSelection;
  final (int, int)? range;
  final ValueChanged<(int, int)?>? onRangeChanged;
  final bool pickRange;
  const _MarketLineChartInteraction({
    required this.renderer,
    required this.rowLabel,
    this.candleTooltipTitle,
    this.candleTooltipRows,
    this.stickyTooltip = false,
    this.externalSelection,
    this.range,
    this.onRangeChanged,
    this.pickRange = false,
  });

  @override
  State<_MarketLineChartInteraction> createState() =>
      _MarketLineChartInteractionState();
}

class _MarketLineChartInteractionState
    extends State<_MarketLineChartInteraction> {
  final ValueNotifier<int?> _ownedSelection = ValueNotifier(null);
  ValueNotifier<int?> get _activeIndex =>
      widget.externalSelection ?? _ownedSelection;

  final _keyboardFocus = FocusNode(debugLabel: 'Chart');
  (int, int)? _zoom;
  Offset? _dragStart;
  double? _dragX;
  int? _dragPointer;
  int? _tapRangeStart;
  int? _rangePointer;
  bool _scrubFrameScheduled = false;
  int? _pendingScrubIndex;

  (int, int)? get _range => widget.range ?? _zoom;

  _MarketLineChartRenderer get _renderer => _range == null
      ? widget.renderer
      : widget.renderer.zoomTo(_range!.$1, _range!.$2);

  void _setRange((int, int)? range) {
    setState(() {
      _zoom = widget.onRangeChanged == null ? range : null;
      _tapRangeStart = null;
      _clear();
    });
    widget.onRangeChanged?.call(range);
  }

  bool get _isMobileChart => switch (Theme.of(context).platform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  void _pickRangeDot(ChartScene scene, Offset position) {
    if (!widget.pickRange || !_isMobileChart) return;
    final bounds = scene.bounds;
    if (bounds == null) return;
    final index = ChartHitTest.nearestIndexAtX(scene, position.dx);
    if (index == null) return;
    final start = _tapRangeStart;
    if (start == null) {
      setState(() => _tapRangeStart = index);
      return;
    }
    if (start == index) return;
    _setRange((min(start, index), max(start, index)));
  }

  Future<void> _showStartDateMenu(
    Offset globalPosition,
    int start,
    int end,
  ) async {
    final dataSignature = widget.renderer.dataSignature;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          enabled: start < end,
          child: const Text('Start from this date'),
        ),
      ],
    );
    if (!mounted ||
        selected != true ||
        !listEquals(dataSignature, widget.renderer.dataSignature)) return;
    _setRange((start, end));
    setState(() {
      _dragStart = null;
      _dragX = null;
      _dragPointer = null;
      _clear();
    });
  }

  void _activate(Offset position, ChartScene scene) {
    _activeIndex.value = ChartHitTest.nearestIndexAtX(scene, position.dx);
  }

  void _activateScrub(Offset position, ChartScene scene) {
    final index = ChartHitTest.nearestIndexAtX(scene, position.dx);
    if (index == null) {
      _clear();
      return;
    }
    if (ChartHitTest.marksAtIndex(scene, index).length <= 1) {
      _pendingScrubIndex = null;
      _activeIndex.value = index;
      return;
    }
    _pendingScrubIndex = index;
    if (_scrubFrameScheduled) return;
    _scrubFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scrubFrameScheduled = false;
      final pending = _pendingScrubIndex;
      _pendingScrubIndex = null;
      if (mounted && pending != null) _activeIndex.value = pending;
    });
  }

  void _clear() {
    _pendingScrubIndex = null;
    _activeIndex.value = null;
  }

  bool get _keepTooltipOnTapUp {
    if (widget.stickyTooltip) return true;
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      _ => false,
    };
  }

  @override
  void didUpdateWidget(_MarketLineChartInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
      oldWidget.renderer.dataSignature,
      widget.renderer.dataSignature,
    )) {
      _zoom = null;
      _dragStart = null;
      _dragX = null;
      _dragPointer = null;
      _tapRangeStart = null;
      _clear();
    }
    if (oldWidget.pickRange != widget.pickRange) _tapRangeStart = null;
    if (oldWidget.stickyTooltip != widget.stickyTooltip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clear();
      });
    }
    final index = _activeIndex.value;
    if (index != null && !_renderer.hasIndex(index)) _clear();
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    _pendingScrubIndex = null;
    _ownedSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = dark ? DrafterThemeColors.dark : DrafterThemeColors.light;

    return ValueListenableBuilder<int?>(
      valueListenable: _activeIndex,
      builder: (context, activeIndex, chart) => PopScope(
        canPop: widget.externalSelection != null ||
            !widget.stickyTooltip ||
            activeIndex == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.externalSelection == null) _clear();
        },
        child: chart!,
      ),
      child: TapRegion(
        onTapOutside: (_) {
          if (widget.stickyTooltip) _clear();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final renderer = _renderer;
            final scene = renderer.buildScene(size);
            final bounds = scene.bounds;
            final startDot = _tapRangeStart == null
                ? null
                : scene.marks
                    .where((mark) => mark.index == _tapRangeStart)
                    .firstOrNull
                    ?.center;
            final rangeStartX = _dragStart?.dx;
            final rangeEndX = _dragX;
            final rangeLeft =
                rangeStartX != null && rangeEndX != null && bounds != null
                    ? min(rangeStartX, rangeEndX)
                        .clamp(bounds.left, bounds.right)
                        .toDouble()
                    : null;
            final rangeRight =
                rangeStartX != null && rangeEndX != null && bounds != null
                    ? max(rangeStartX, rangeEndX)
                        .clamp(bounds.left, bounds.right)
                        .toDouble()
                    : null;

            return Focus(
              focusNode: _keyboardFocus,
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                final indices = scene.marks
                    .map((mark) => mark.index)
                    .toSet()
                    .toList()
                  ..sort();
                if (indices.isEmpty) return KeyEventResult.ignored;
                final current = indices.indexOf(_activeIndex.value ?? -1);
                if (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.home ||
                    key == LogicalKeyboardKey.end) {
                  final next = switch (true) {
                    _ when key == LogicalKeyboardKey.home => 0,
                    _ when key == LogicalKeyboardKey.end => indices.length - 1,
                    _ when current < 0 => 0,
                    _ => (current +
                            (key == LogicalKeyboardKey.arrowRight ? 1 : -1))
                        .clamp(0, indices.length - 1),
                  };
                  _activeIndex.value = indices[next];
                } else if (key == LogicalKeyboardKey.enter &&
                    widget.pickRange &&
                    _activeIndex.value != null) {
                  final index = _activeIndex.value!;
                  if (_tapRangeStart == null) {
                    setState(() => _tapRangeStart = index);
                  } else if (_tapRangeStart != index) {
                    _setRange(
                      (
                        min(_tapRangeStart!, index),
                        max(_tapRangeStart!, index)
                      ),
                    );
                  }
                } else if (key == LogicalKeyboardKey.keyR) {
                  _setRange(null);
                } else {
                  return KeyEventResult.ignored;
                }
                return KeyEventResult.handled;
              },
              child: MouseRegion(
                onHover: (event) => _activate(event.localPosition, scene),
                onExit: (_) {
                  if (_dragPointer == null) _clear();
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _activate(event.localPosition, scene);
                    if (widget.pickRange &&
                        _isMobileChart &&
                        event.kind == PointerDeviceKind.touch &&
                        _rangePointer == null &&
                        bounds != null &&
                        Rect.fromLTRB(
                          bounds.left,
                          bounds.top,
                          bounds.right,
                          bounds.bottom,
                        ).contains(event.localPosition)) {
                      _rangePointer = event.pointer;
                    }
                    if (event.kind == PointerDeviceKind.mouse &&
                        event.buttons == kPrimaryMouseButton &&
                        bounds != null &&
                        Rect.fromLTRB(
                          bounds.left,
                          bounds.top,
                          bounds.right,
                          bounds.bottom,
                        ).contains(event.localPosition)) {
                      _dragStart = event.localPosition;
                      _dragPointer = event.pointer;
                    }
                  },
                  onPointerMove: (event) {
                    if (event.pointer == _rangePointer) {
                      _activateScrub(event.localPosition, scene);
                      return;
                    }
                    if (event.pointer != _dragPointer || _dragStart == null)
                      return;
                    setState(() {
                      _dragX = event.localPosition.dx;
                    });
                    _activate(event.localPosition, scene);
                  },
                  onPointerUp: (event) {
                    if (event.pointer == _rangePointer) {
                      _rangePointer = null;
                      _pickRangeDot(scene, event.localPosition);
                    }
                    if (event.pointer == _dragPointer) {
                      final start = _dragStart;
                      if (start != null &&
                          (event.localPosition.dx - start.dx).abs() >= 8) {
                        final first =
                            ChartHitTest.nearestIndexAtX(scene, start.dx);
                        final last = ChartHitTest.nearestIndexAtX(
                          scene,
                          event.localPosition.dx,
                        );
                        if (first != null && last != null && first != last) {
                          _setRange((min(first, last), max(first, last)));
                        }
                      }
                      setState(() {
                        _dragStart = null;
                        _dragX = null;
                        _dragPointer = null;
                        _clear();
                      });
                    } else {
                      _activate(event.localPosition, scene);
                    }
                    if (!_keepTooltipOnTapUp) _clear();
                  },
                  onPointerCancel: (event) => setState(() {
                    if (event.pointer == _rangePointer) _rangePointer = null;
                    _dragStart = null;
                    _dragX = null;
                    _dragPointer = null;
                    _clear();
                  }),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapUp: (details) {
                      final bounds = scene.bounds;
                      if (bounds == null ||
                          !Rect.fromLTRB(
                            bounds.left,
                            bounds.top,
                            bounds.right,
                            bounds.bottom,
                          ).contains(details.localPosition)) return;
                      final start = ChartHitTest.nearestIndexAtX(
                        scene,
                        details.localPosition.dx,
                      );
                      if (start == null || scene.marks.isEmpty) return;
                      final end =
                          scene.marks.map((mark) => mark.index).reduce(max);
                      unawaited(
                        _showStartDateMenu(details.globalPosition, start, end),
                      );
                    },
                    onLongPressStart: (details) =>
                        _activate(details.localPosition, scene),
                    onLongPressMoveUpdate: (details) =>
                        _activateScrub(details.localPosition, scene),
                    onLongPressEnd: (_) {
                      if (_dragPointer == null && !widget.stickyTooltip)
                        _clear();
                    },
                    onLongPressCancel: () {
                      if (_dragPointer == null && !widget.stickyTooltip)
                        _clear();
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DrafterTheme(
                          colors: theme,
                          child: ChartCanvas(
                            renderer: renderer,
                            animate: false,
                          ),
                        ),
                        if (rangeLeft != null &&
                            rangeRight != null &&
                            bounds != null)
                          Positioned(
                            left: rangeLeft,
                            top: bounds.top,
                            width: rangeRight - rangeLeft,
                            height: bounds.height,
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        if (startDot != null && widget.pickRange) ...[
                          Positioned(
                            left: startDot.dx - 1,
                            top: bounds?.top ?? 0,
                            width: 2,
                            height: bounds?.height ?? size.height,
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          Positioned(
                            left: startDot.dx - 7,
                            top: startDot.dy - 7,
                            width: 14,
                            height: 14,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                key: const Key('chart-range-start-dot'),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _MarketLineTooltipPainter(
                                  activeIndex: _activeIndex,
                                  scene: scene,
                                  theme: theme,
                                  rowLabel: widget.rowLabel,
                                  candleTooltipTitle: widget.candleTooltipTitle,
                                  candleTooltipRows: widget.candleTooltipRows,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
