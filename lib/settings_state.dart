import 'package:flutter/material.dart';

class SettingsState extends ChangeNotifier {
  ThemeMode theme = ThemeMode.system;

  SettingsState(ThemeMode? value) {
    if (value != null) theme = value;
    notifyListeners();
  }

  void setTheme(ThemeMode value) {
    theme = value;
    notifyListeners();
  }
}
