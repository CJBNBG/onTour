import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/speed_accuracy_mode.dart';
import '../models/speed_unit.dart';

/// Zentrale, persistierte App-Einstellungen: Anzeigemodus (System/Dark/
/// Light), zuletzt gewählte Geschwindigkeits-Einheit, die gewählte
/// Genauigkeits-/Akku-Stufe für die Geschwindigkeitsmessung sowie die
/// zuletzt gewählte Kartendarstellung (Landkarte/Seekarte).
///
/// Bewusst als einfache [ChangeNotifier]-Klasse umgesetzt (kein
/// zusätzliches State-Management-Paket nötig): Widgets, die auf
/// Änderungen reagieren sollen, hören per [AnimatedBuilder]/
/// [ListenableBuilder] auf diese eine Instanz (siehe main.dart).
class AppPreferences extends ChangeNotifier {
  static const _themeModeKey = 'themeMode';
  static const _speedUnitKey = 'speedUnit';
  static const _speedAccuracyModeKey = 'speedAccuracyMode';
  static const _mapNauticalModeKey = 'mapNauticalMode';

  ThemeMode _themeMode = ThemeMode.system;
  SpeedUnit _speedUnit = SpeedUnit.kilometersPerHour;
  SpeedAccuracyMode _speedAccuracyMode = SpeedAccuracyMode.balanced;
  bool _mapNauticalMode = false;

  ThemeMode get themeMode => _themeMode;
  SpeedUnit get speedUnit => _speedUnit;
  SpeedAccuracyMode get speedAccuracyMode => _speedAccuracyMode;

  /// true = Seekarte (Landkarte + Seemarken-Overlay von OpenSeaMap),
  /// false = normale Landkarte (siehe TrackPage/TrackDetailPage sowie
  /// widgets/nautical_mode_button.dart).
  bool get mapNauticalMode => _mapNauticalMode;

  /// Lädt zuvor gespeicherte Einstellungen (falls vorhanden). Muss einmal
  /// beim App-Start aufgerufen werden, bevor runApp() erfolgt bzw. bevor
  /// die erste Anzeige davon abhängt.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final storedThemeMode = prefs.getString(_themeModeKey);
    if (storedThemeMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == storedThemeMode,
        orElse: () => ThemeMode.system,
      );
    }

    final storedSpeedUnit = prefs.getString(_speedUnitKey);
    if (storedSpeedUnit != null) {
      _speedUnit = SpeedUnit.values.firstWhere(
        (unit) => unit.name == storedSpeedUnit,
        orElse: () => SpeedUnit.kilometersPerHour,
      );
    }

    final storedAccuracyMode = prefs.getString(_speedAccuracyModeKey);
    if (storedAccuracyMode != null) {
      _speedAccuracyMode = SpeedAccuracyMode.values.firstWhere(
        (mode) => mode.name == storedAccuracyMode,
        orElse: () => SpeedAccuracyMode.balanced,
      );
    }

    final storedMapNauticalMode = prefs.getBool(_mapNauticalModeKey);
    if (storedMapNauticalMode != null) {
      _mapNauticalMode = storedMapNauticalMode;
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setSpeedUnit(SpeedUnit unit) async {
    _speedUnit = unit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedUnitKey, unit.name);
  }

  Future<void> setSpeedAccuracyMode(SpeedAccuracyMode mode) async {
    _speedAccuracyMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedAccuracyModeKey, mode.name);
  }

  Future<void> setMapNauticalMode(bool nautical) async {
    _mapNauticalMode = nautical;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mapNauticalModeKey, nautical);
  }
}
