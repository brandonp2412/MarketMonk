import 'dart:io';

import 'src/market_monk_cli.dart';

void main(List<String> arguments) {
  exitCode = MarketMonkCli().run(arguments);
}
