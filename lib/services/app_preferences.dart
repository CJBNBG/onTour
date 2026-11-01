import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_style.dart';
import '../models/place_result.dart';
import '../models/route_overlay.dart';
import '../models/position_display_format.dart';
import '../models/speed_accuracy_mode.dart';
import '../models/speed_display_style.dart';
import '../models/speed_scale.dart';
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
  static const _mapStyleKey = 'mapStyle';
  static const _routeOverlayKey = 'routeOverlay';
  static const _autoPauseReminderMinutesKey = 'autoPauseReminderMinutes';
  static const _positionDisplayFormatKey = 'positionDisplayFormat';
  static const _destinationKey = 'destination';
  static const _speedDisplayStyleKey = 'speedDisplayStyle';
  static const _speedScaleMaxKeyPrefix = 'speedScaleMax_';

  ThemeMode _themeMode = ThemeMode.system;
  SpeedUnit _speedUnit = SpeedUnit.kilometersPerHour;
  SpeedAccuracyMode _speedAccuracyMode = SpeedAccuracyMode.balanced;
  bool _mapNauticalMode = false;
  MapStyle _mapStyle = MapStyle.standard;
  RouteOverlay _routeOverlay = RouteOverlay.none;
  int _autoPauseReminderMinutes = 3;
  PositionDisplayFormat _positionDisplayFormat = PositionDisplayFormat.dms;
  PlaceResult? _destination;
  SpeedDisplayStyle _speedDisplayStyle = SpeedDisplayStyle.digital;
  final Map<SpeedUnit, int> _speedScaleMax = {};

  ThemeMode get themeMode => _themeMode;
  SpeedUnit get speedUnit => _speedUnit;
  SpeedAccuracyMode get speedAccuracyMode => _speedAccuracyMode;

  /// Wartezeit, nach der eine anhaltend pausierte Track-Aufzeichnung per
  /// Benachrichtigung in Erinnerung gerufen wird (siehe README Abschnitt
  /// 22, TrackRecordingService). Standard: 3 Minuten, 0 = Erinnerung aus.
  int get autoPauseReminderMinutes => _autoPauseReminderMinutes;

  /// Anzeigeformat für die aktuelle Position auf der Kompass-Seite (siehe
  /// README Abschnitt 25). Standard: DMS (bisheriges, einziges Format).
  PositionDisplayFormat get positionDisplayFormat => _positionDisplayFormat;

  /// NEU (siehe README Abschnitt 50): Das auf der Track-Seite markierte
  /// Ziel (Ortssuche bzw. langes Drücken auf die Karte) - null, wenn keins
  /// gesetzt ist. Bleibt über App-Neustarts erhalten.
  PlaceResult? get destination => _destination;

  /// Darstellung der Geschwindigkeit auf der Tacho-Seite (digital/analog).
  SpeedDisplayStyle get speedDisplayStyle => _speedDisplayStyle;

  /// Skalenende des analogen Tachos - je Einheit separat gespeichert.
  int speedScaleMax(SpeedUnit unit) => _speedScaleMax[unit] ?? SpeedScale.defaultFor(unit);

  /// true = Seekarte (Landkarte + Seemarken-Overlay von OpenSeaMap),
  /// false = normale Landkarte (siehe TrackPage/TrackDetailPage sowie
  /// widgets/nautical_mode_button.dart).
  bool get mapNauticalMode => _mapNauticalMode;

  /// NEU (siehe README Abschnitt 51): Gewählte Basiskarte (Standard,
  /// OpenTopoMap-R, Reit- und Wanderkarte). Das Seemarken-Overlay
  /// ([mapNauticalMode]) lässt sich über jede davon legen.
  MapStyle get mapStyle => _mapStyle;

  /// NEU (siehe README Abschnitt 52): Gewähltes Routen-Overlay (Wander-/
  /// Radrouten von Waymarked Trails), Standard: aus.
  RouteOverlay get routeOverlay => _routeOverlay;

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

    final storedMapStyle = prefs.getString(_mapStyleKey);
    if (storedMapStyle != null) {
      _mapStyle = MapStyle.values.firstWhere(
        (style) => style.name == storedMapStyle,
        orElse: () => MapStyle.standard,
      );
    }

    final storedRouteOverlay = prefs.getString(_routeOverlayKey);
    if (storedRouteOverlay != null) {
      _routeOverlay = RouteOverlay.values.firstWhere(
        (overlay) => overlay.name == storedRouteOverlay,
        orElse: () => RouteOverlay.none,
      );
    }

    final storedReminderMinutes = prefs.getInt(_autoPauseReminderMinutesKey);
    if (storedReminderMinutes != null && storedReminderMinutes >= 0) {
      _autoPauseReminderMinutes = storedReminderMinutes;
    }

    final storedPositionDisplayFormat = prefs.getString(_positionDisplayFormatKey);
    if (storedPositionDisplayFormat != null) {
      _positionDisplayFormat = PositionDisplayFormat.values.firstWhere(
        (format) => format.name == storedPositionDisplayFormat,
        orElse: () => PositionDisplayFormat.dms,
      );
    }

    final storedDestination = prefs.getString(_destinationKey);
    if (storedDestination != null) {
      try {
        _destination = PlaceResult.fromJson(
          jsonDecode(storedDestination) as Map<String, dynamic>,
        );
      } catch (_) {
        _destination = null; // beschädigter Eintrag - ohne Ziel starten
      }
    }

    final storedDisplayStyle = prefs.getString(_speedDisplayStyleKey);
    if (storedDisplayStyle != null) {
      _speedDisplayStyle = SpeedDisplayStyle.values.firstWhere(
        (style) => style.name == storedDisplayStyle,
        orElse: () => SpeedDisplayStyle.digital,
      );
    }
    for (final unit in SpeedUnit.values) {
      final stored = prefs.getInt('$_speedScaleMaxKeyPrefix${unit.name}');
      if (stored != null && SpeedScale.isValid(unit, stored)) {
        _speedScaleMax[unit] = stored;
      }
    }

    notifyListeners();
  }

  Future<void> setSpeedDisplayStyle(SpeedDisplayStyle style) async {
    _speedDisplayStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedDisplayStyleKey, style.name);
  }

  Future<void> setSpeedScaleMax(SpeedUnit unit, int value) async {
    if (!SpeedScale.isValid(unit, value)) return;
    _speedScaleMax[unit] = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_speedScaleMaxKeyPrefix${unit.name}', value);
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

  Future<void> setRouteOverlay(RouteOverlay overlay) async {
    _routeOverlay = overlay;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeOverlayKey, overlay.name);
  }

  Future<void> setMapStyle(MapStyle style) async {
    _mapStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapStyleKey, style.name);
  }

  /// HINWEIS: Wirkt sich (analog zu setSpeedAccuracyMode, siehe Abschnitt
  /// 4) erst auf die NÄCHSTE Pause aus, nicht rückwirkend auf eine
  /// bereits laufende, bereits geplante Erinnerung - siehe README
  /// Abschnitt 22.
  Future<void> setAutoPauseReminderMinutes(int minutes) async {
    _autoPauseReminderMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoPauseReminderMinutesKey, minutes);
  }

  /// Wirkt sich sofort aus (ListenableBuilder in CompassPage, siehe
  /// README Abschnitt 25) - anders als z. B. die Genauigkeitsstufe der
  /// Geschwindigkeitsmessung ist hierfür kein Neustart eines Sensor-
  /// Streams nötig, es ändert sich lediglich die Textdarstellung eines
  /// bereits vorliegenden Werts.
  Future<void> setPositionDisplayFormat(PositionDisplayFormat format) async {
    _positionDisplayFormat = format;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_positionDisplayFormatKey, format.name);
  }

  /// NEU (README Abschnitt 50): Setzt bzw. (mit null) entfernt das Ziel.
  Future<void> setDestination(PlaceResult? place) async {
    _destination = place;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (place == null) {
      await prefs.remove(_destinationKey);
    } else {
      await prefs.setString(_destinationKey, jsonEncode(place.toJson()));
    }
  }
}
