import 'package:flutter/material.dart';
import 'package:market_monk/debug_hotkeys.dart';
import 'package:market_monk/ibkr_api.dart';

class IbkrCandleFailureNotice {
  IbkrCandleFailureNotice({
    this.quietPeriod = const Duration(minutes: 10),
    DateTime Function()? clock,
    ScaffoldMessengerState? Function()? messenger,
  }) : _clock = clock ?? DateTime.now,
       _messenger = messenger ?? (() => debugHotkeyMessengerKey.currentState);

  final Duration quietPeriod;
  final DateTime Function() _clock;
  final ScaffoldMessengerState? Function() _messenger;
  DateTime? _lastShownAt;
  bool _pending = false;

  void report(String symbol, Object error) {
    if (_pending || _recentlyShown()) return;
    _pending = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _pending = false;
      final messenger = _messenger();
      if (messenger == null || !messenger.mounted || _recentlyShown()) return;
      final description = error is IbkrRateLimitException
          ? 'IBKR rate limited (HTTP 429). Using Yahoo candles.'
          : 'IBKR candle sync failed for $symbol. Using Yahoo candles.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(description),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
      _lastShownAt = _clock();
    });
    binding.scheduleFrame();
  }

  bool _recentlyShown() {
    final lastShown = _lastShownAt;
    return lastShown != null && _clock().difference(lastShown) < quietPeriod;
  }
}

final ibkrCandleFailureNotice = IbkrCandleFailureNotice();
