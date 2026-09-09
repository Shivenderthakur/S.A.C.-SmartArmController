import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arm_link.dart';

/// Everything the user can change and expects to survive a restart.
///
/// Changes apply the moment they are made - the whole app listens to this, so
/// a theme switch repaints without a reload.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _kTheme = 'theme_mode';
  static const _kAccent = 'accent';
  static const _kHost = 'esp32_host';
  static const _kStream = 'stream_enabled';
  static const _kInterval = 'send_interval_ms';
  static const _kMirror = 'mirror_overlay';
  static const _kTransport = 'transport';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt(_kTheme) ?? ThemeMode.system.index];
  set themeMode(ThemeMode v) {
    _prefs.setInt(_kTheme, v.index);
    notifyListeners();
  }

  /// Index into [accents].
  int get accent => _prefs.getInt(_kAccent) ?? 0;
  set accent(int v) {
    _prefs.setInt(_kAccent, v);
    notifyListeners();
  }

  Color get accentColor => accents[accent.clamp(0, accents.length - 1)].$2;

  /// Host or IP of the ESP32, without a scheme. Empty means not configured.
  String get host => _prefs.getString(_kHost) ?? '';
  set host(String v) {
    _prefs.setString(_kHost, v.trim());
    notifyListeners();
  }

  bool get streaming => _prefs.getBool(_kStream) ?? false;
  set streaming(bool v) {
    _prefs.setBool(_kStream, v);
    notifyListeners();
  }

  /// Floor on the gap between two commands. The arm cannot keep up with 25 Hz
  /// and neither can a small HTTP server.
  int get sendIntervalMs => _prefs.getInt(_kInterval) ?? 80;
  set sendIntervalMs(int v) {
    _prefs.setInt(_kInterval, v);
    notifyListeners();
  }

  /// HTTP by default: a board already flashed with the old sketch keeps
  /// working after an update, and the socket is one tap away on the Arm screen.
  ArmTransport get transport =>
      ArmTransport.values[(_prefs.getInt(_kTransport) ?? 0)
          .clamp(0, ArmTransport.values.length - 1)];
  set transport(ArmTransport v) {
    _prefs.setInt(_kTransport, v.index);
    notifyListeners();
  }

  bool get mirrorOverlay => _prefs.getBool(_kMirror) ?? true;
  set mirrorOverlay(bool v) {
    _prefs.setBool(_kMirror, v);
    notifyListeners();
  }

  static const accents = <(String, Color)>[
    ('Teal', Color(0xFF00A99D)),
    ('Violet', Color(0xFF7C4DFF)),
    ('Amber', Color(0xFFFFA000)),
    ('Crimson', Color(0xFFD32F2F)),
    ('Ocean', Color(0xFF0288D1)),
  ];
}
