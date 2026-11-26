import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/debug_hotkeys.dart';
import 'package:url_launcher/url_launcher.dart';

enum WebMarketProblem { rateLimited, unavailable }

const nativeReleasesUrl =
    'https://github.com/brandonp2412/MarketMonk/releases/latest';

WebMarketProblem? classifyWebMarketResponse(http.Response response) {
  if (response.statusCode == 429 ||
      (response.statusCode >= 400 &&
          response.headers['content-type']?.contains('text/html') == true &&
          RegExp(
            r'\b(?:error\s*(?:code\s*)?:?\s*1027|1027\s*:)\b',
            caseSensitive: false,
          ).hasMatch(response.body))) {
    return WebMarketProblem.rateLimited;
  }
  return null;
}

class WebRateLimitNotice {
  WebRateLimitNotice({
    this.quietPeriod = const Duration(minutes: 2),
    DateTime Function()? clock,
    ScaffoldMessengerState? Function()? messenger,
    Future<bool> Function(Uri)? openUrl,
  })  : _clock = clock ?? DateTime.now,
        _messenger = messenger ?? (() => debugHotkeyMessengerKey.currentState),
        _openUrl = openUrl ??
            ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final Duration quietPeriod;
  final DateTime Function() _clock;
  final ScaffoldMessengerState? Function() _messenger;
  final Future<bool> Function(Uri) _openUrl;
  final Map<WebMarketProblem, DateTime> _shown = {};
  WebMarketProblem? _pending;

  void report(WebMarketProblem problem) {
    if (_recentlyShown(problem)) return;
    if (_pending != null) {
      if (problem == WebMarketProblem.rateLimited) _pending = problem;
      return;
    }
    _pending = problem;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      final pending = _pending;
      _pending = null;
      final messenger = _messenger();
      if (pending == null ||
          messenger == null ||
          !messenger.mounted ||
          _recentlyShown(pending)) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            pending == WebMarketProblem.rateLimited
                ? 'Web market data limit hit. Native apps have no web quota.'
                : 'Web market data unavailable (possibly rate limited). Native apps bypass the web quota.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          persist: false,
          action: SnackBarAction(
            label: 'Download native app',
            onPressed: () => unawaited(_openUrl(Uri.parse(nativeReleasesUrl))),
          ),
        ),
      );
      _shown[pending] = _clock();
    });
    binding.scheduleFrame();
  }

  bool _recentlyShown(WebMarketProblem problem) {
    final last = _shown[problem];
    return last != null && _clock().difference(last) < quietPeriod;
  }
}

final webRateLimitNotice = WebRateLimitNotice();
