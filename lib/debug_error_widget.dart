import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

final debugFlutterError = ValueNotifier<FlutterErrorDetails?>(null);

void reportDebugFlutterError(FlutterErrorDetails details) {
  if (kDebugMode && details.context == null) debugFlutterError.value = details;
}

void installDebugErrorWidget() {
  if (!kDebugMode) return;
  ErrorWidget.builder = (details) => DebugErrorScreen(details: details);
}

class DebugErrorScreen extends StatelessWidget {
  const DebugErrorScreen({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stack = details.stack?.toString() ?? 'No stack trace was provided.';
    final source = _sourceExcerpt(stack);
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bug_report_rounded, color: colors.error, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'A widget hit an error',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'DEBUG',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      details.exceptionAsString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.error,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy error',
                    icon: const Icon(Icons.content_copy_rounded, size: 19),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: details.exceptionAsString()),
                    ),
                  ),
                ],
              ),
              if (source != null) ...[
                const SizedBox(height: 20),
                Text(
                  source.location,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    source.lines,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stack trace',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy stack trace',
                    icon: const Icon(Icons.content_copy_rounded, size: 19),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: stack)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    stack,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({String location, String lines})? _sourceExcerpt(String stack) {
  final frame =
      RegExp(r'(package:[^\s():]+|file://[^\s():]+|/[^\s():]+):(\d+):(\d+)')
          .firstMatch(stack);
  if (frame == null) return null;
  final uri = frame.group(1)!;
  final lineNumber = int.parse(frame.group(2)!);
  var filePath = uri;
  if (uri.startsWith('package:')) {
    final packagePath = uri.substring('package:'.length);
    final separator = packagePath.indexOf('/');
    if (separator < 0) return null;
    filePath = p.join(
      Directory.current.path,
      'lib',
      packagePath.substring(separator + 1),
    );
  } else if (uri.startsWith('file://')) {
    filePath = Uri.parse(uri).toFilePath();
  }
  try {
    final lines = File(filePath).readAsLinesSync();
    if (lineNumber < 1 || lineNumber > lines.length) return null;
    final start = (lineNumber - 3).clamp(1, lines.length);
    final end = (lineNumber + 1).clamp(1, lines.length);
    final excerpt = <String>[];
    for (var index = start; index <= end; index++) {
      excerpt.add(
        '${index == lineNumber ? '›' : ' '} ${index.toString().padLeft(4)}  ${lines[index - 1]}',
      );
    }
    return (location: '$uri:$lineNumber', lines: excerpt.join('\n'));
  } on FileSystemException {
    return null;
  }
}
