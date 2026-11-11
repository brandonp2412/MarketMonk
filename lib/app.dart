import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/debug_hotkeys.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/update_notice.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:market_monk/vi_overlay.dart';
import 'package:market_monk/whats_new.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        scaffoldMessengerKey: debugHotkeyMessengerKey,
        title: 'Market Monk',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [ModalRouteTracker.instance],
        builder: (context, child) => Stack(
          children: [
            if (child != null) ViOverlay(child: child),
            if (kDebugMode)
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: SafeArea(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.code_rounded,
                              size: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'DEBUG',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    decoration: TextDecoration.none,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        theme: ThemeData(
          colorScheme: settings.systemColors
              ? lightDynamic
              : ColorScheme.fromSeed(seedColor: settings.seedColor).copyWith(
                  primary: settings.seedColor == defaultSeedColor
                      ? defaultSeedColor
                      : null,
                  onPrimary: settings.seedColor == defaultSeedColor
                      ? Colors.black
                      : null,
                ),
          useMaterial3: true,
          sliderTheme: const SliderThemeData(
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
          popupMenuTheme: const PopupMenuThemeData(
            menuPadding: EdgeInsets.zero,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: (settings.systemColors
                  ? (darkDynamic ??
                      ColorScheme.fromSeed(
                        seedColor: settings.seedColor,
                        brightness: Brightness.dark,
                      ))
                  : ColorScheme.fromSeed(
                      seedColor: settings.seedColor,
                      brightness: Brightness.dark,
                    ))
              .copyWith(
            surface: settings.pureBlack ? Colors.black : null,
            primary:
                !settings.systemColors && settings.seedColor == defaultSeedColor
                    ? defaultSeedColor
                    : null,
            onPrimary:
                !settings.systemColors && settings.seedColor == defaultSeedColor
                    ? Colors.black
                    : null,
          ),
          useMaterial3: true,
          sliderTheme: const SliderThemeData(
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
          popupMenuTheme: const PopupMenuThemeData(
            menuPadding: EdgeInsets.zero,
          ),
        ),
        themeMode: settings.theme,
        locale: settings.locale,
        localeResolutionCallback: AppLocalizations.resolveLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const MyHomePage(),
      ),
    );
  }
}

/// Broadcasts requests to show a specific ticker in the persistent charts tab.
class ChartsFocusController {
  ChartsFocusController._();

  static final instance = ChartsFocusController._();

  final _requests = StreamController<String>.broadcast();

  Stream<String> get requests => _requests.stream;

  void focus(String symbol) => _requests.add(symbol);
}

void openAppSettings(BuildContext context) {
  final home = context.findAncestorStateOfType<_MyHomePageState>();
  if (home != null) {
    home._selectDesktopSettings();
  } else {
    Navigator.of(context)
        .push(adaptivePageRoute(context, builder: (_) => const SettingsPage()));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final PageController _pageController;
  late final ValueNotifier<int> _selectedPage;
  late int _currentIndex;
  bool _desktopSettingsSelected = false;
  bool _hasOpenedDesktopSettings = false;
  StreamSubscription<String>? _chartsFocusSubscription;

  static const _tabs = ['ChartPage', 'PortfolioPage', 'HoldingsPage'];

  @override
  void initState() {
    super.initState();
    final startPage = context.read<SettingsState>().startPage;
    _pageController = PageController(initialPage: startPage);
    _selectedPage = ValueNotifier<int>(startPage);
    _currentIndex = startPage;
    _chartsFocusSubscription = ChartsFocusController.instance.requests
        .listen((_) => _selectDesktopPage(0));
    ViNavigation.instance.openSettings = _selectDesktopSettings;
    ViNavigation.instance.closeSettings = _closeSettings;
    ViNavigation.instance.selectTab = _selectDesktopPage;
    ViNavigation.instance.fallbackSearch = _openViSearch;
    ViNavigation.instance.fallbackMoveFocus = _openViHoldingsFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateNotice());
  }

  Future<void> _showUpdateNotice() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber);
      if (build == null) return;
      final prefs = await SqliteSettings.getInstance();
      const buildKey = 'last_seen_build_number';
      const noticeKey = 'last_update_notice_ms';
      final previousBuild = prefs.getInt(buildKey);
      if (previousBuild == null || build > previousBuild) {
        await prefs.setInt(buildKey, build);
      }
      if (!mounted || prefs.getBool(showUpdateNoticesKey) == false) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!shouldShowUpdateNotice(
        previousBuild: previousBuild,
        currentBuild: build,
        lastShownAtMs: prefs.getInt(noticeKey),
        nowMs: now,
      )) return;
      await prefs.setInt(noticeKey, now);
      if (!mounted) return;
      toast(
        context,
        'New version ${info.version}',
        SnackBarAction(
          label: context.l10n.text("What's New"),
          onPressed: () => Navigator.of(
            context,
          ).push(adaptivePageRoute(context, builder: (_) => const WhatsNew())),
        ),
      );
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Unable to show MarketMonk update notice',
      );
    }
  }

  @override
  void dispose() {
    ViNavigation.instance.openSettings = null;
    ViNavigation.instance.closeSettings = null;
    ViNavigation.instance.selectTab = null;
    ViNavigation.instance.fallbackSearch = null;
    ViNavigation.instance.fallbackMoveFocus = null;
    unawaited(_chartsFocusSubscription?.cancel());
    _pageController.dispose();
    _selectedPage.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (_desktopSettingsSelected)
      setState(() => _desktopSettingsSelected = false);
    _selectedPage.value = index;
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _openViHoldingsFocus(int delta) {
    _selectDesktopPage(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentIndex == 2 && !_desktopSettingsSelected) {
        ViNavigation.instance.target?.moveFocus(delta);
      }
    });
  }

  void _openViSearch() {
    _selectDesktopPage(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentIndex == 0 && !_desktopSettingsSelected) {
        ViNavigation.instance.target?.requestSearch();
      }
    });
  }

  void _selectDesktopPage(int index) {
    ViNavigation.instance.focusedContext.value = null;
    if (index == _currentIndex && !_desktopSettingsSelected) return;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    _selectedPage.value = index;
    setState(() {
      _currentIndex = index;
      _desktopSettingsSelected = false;
    });
  }

  bool _closeSettings() {
    if (!_desktopSettingsSelected) return false;
    setState(() => _desktopSettingsSelected = false);
    return true;
  }

  void _selectDesktopSettings() {
    ViNavigation.instance.focusedContext.value = null;
    if (_desktopSettingsSelected) return;
    setState(() {
      _desktopSettingsSelected = true;
      _hasOpenedDesktopSettings = true;
    });
  }

  bool _onPageScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final settledIndex = _pageController.page?.round() ?? _selectedPage.value;
    if (settledIndex != _currentIndex) {
      setState(() => _currentIndex = settledIndex);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return PopScope(
      canPop: !_desktopSettingsSelected,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSettings();
      },
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= desktopLayoutBreakpoint;
              final settingsVisible = _desktopSettingsSelected;
              final pages = NotificationListener<ScrollEndNotification>(
                onNotification: _onPageScrollEnd,
                child: PageView(
                  controller: _pageController,
                  allowImplicitScrolling: true,
                  physics: desktop
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (index) => _selectedPage.value = index,
                  children: [
                    !settingsVisible && _currentIndex == 0
                        ? const ChartsPage()
                        : const ChartsPage(isActive: false),
                    !settingsVisible && _currentIndex == 1
                        ? const PortfolioPage()
                        : const PortfolioPage(isActive: false),
                    !settingsVisible && _currentIndex == 2
                        ? const HoldingsPage()
                        : const HoldingsPage(isActive: false),
                  ],
                ),
              );

              final content = Stack(
                children: [
                  IndexedStack(
                    index: settingsVisible ? 1 : 0,
                    children: [
                      pages,
                      if (_hasOpenedDesktopSettings)
                        SettingsPage(
                          isActive: settingsVisible,
                          onClose: _closeSettings,
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                  if (!desktop)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _selectedPage,
                        builder: (context, selectedIndex, _) => BottomNav(
                          tabs: _tabs,
                          currentIndex: selectedIndex,
                          onTap: _selectPage,
                        ),
                      ),
                    ),
                ],
              );

              if (!desktop) return content;

              return Row(
                children: [
                  DesktopNav(
                    tabs: _tabs,
                    compact: false,
                    currentIndex:
                        settingsVisible ? _tabs.length : _currentIndex,
                    onTap: _selectDesktopPage,
                    onSettings: _selectDesktopSettings,
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: content,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
