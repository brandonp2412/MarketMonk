import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  ThemeMode theme = ThemeMode.system;
  bool systemColors = false;
  bool curveLines = true;
  double curveSmoothness = 0.35;
  String dateFormat = 'd/M/yy';

  SettingsState() {
    init();
  }

  init() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('theme');

    switch (themeStr) {
      case 'ThemeMode.system':
        theme = ThemeMode.system;
        break;
      case 'ThemeMode.dark':
        theme = ThemeMode.dark;
        break;
      case 'ThemeMode.light':
        theme = ThemeMode.light;
        break;
      default:
        theme = ThemeMode.system;
        break;
    }

    systemColors = prefs.getBool('systemColors') ?? false;
    curveLines = prefs.getBool('curveLines') ?? true;
    curveSmoothness = prefs.getDouble('curveSmoothness') ?? 0.35;
    dateFormat = prefs.getString('dateFormat') ?? 'd/M/yy';

    notifyListeners();
  }

  void setDateFormat(String value) async {
    dateFormat = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('dateFormat', value);
  }

  void setCurveLines(bool value) async {
    curveLines = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('curveLines', value);
  }

  void setCurveSmoothness(double value) async {
    curveSmoothness = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('curveSmoothness', value);
  }

  void setSystemColors(bool value) async {
    systemColors = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('systemColors', value);
  }

  void setTheme(ThemeMode value) {
    theme = value;
    notifyListeners();
  }
}
