import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_style.dart';
import '../models/place_result.dart';
import '../models/route_overlay.dart';
import '../models/position_display_format.dart';
import '../models/speed_accuracy_mode.dart';
import '../models/speed_display_style.dart';
import '../models/speed_scale.dart';
import '../models/speed_unit.dart';
import '../models/start_grid_columns.dart';
import '../models/step_count_mode.dart';
import '../models/user_profile.dart';
import 'altitude_correction.dart';

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

  /// Nur noch zur einmaligen Übernahme alter Einstellungen (siehe [load],
  /// README Abschnitt 60) - Seemarken sind seither ein Wert von RouteOverlay.
  static const _legacyMapNauticalModeKey = 'mapNauticalMode';
  static const _mapStyleKey = 'mapStyle';
  static const _routeOverlayKey = 'routeOverlay';
  static const _autoPauseReminderMinutesKey = 'autoPauseReminderMinutes';
  static const _positionDisplayFormatKey = 'positionDisplayFormat';
  static const _destinationKey = 'destination';
  static const _speedDisplayStyleKey = 'speedDisplayStyle';
  static const _altitudeManualOffsetKey = 'altitudeManualOffsetMeters';
  static const _speedScaleMaxKeyPrefix = 'speedScaleMax_';
  static const _userProfileKey = 'userProfile';
  static const _profileUnitKeyPrefix = 'profileUnit_';
  static const _profileSlotsKeyPrefix = 'profileSlots_';
  static const _startGridColumnsKey = 'startGridColumns';
  static const _stepCountModeKey = 'stepCountMode';
  static const _navigationNoticeVersionKey = 'navigationNoticeVersion';
  static const _navigationNoticeAcceptedAtKey = 'navigationNoticeAcceptedAt';

  /// Version des Hinweises "keine Navigation" (siehe README Abschnitt 70,
  /// util/navigation_notice.dart). ERHÖHEN, wenn sich der Hinweis inhaltlich
  /// wesentlich ändert - dann muss ihn jeder Nutzer erneut bestätigen.
  static const int currentNavigationNoticeVersion = 1;

  ThemeMode _themeMode = ThemeMode.system;
  SpeedUnit _speedUnit = SpeedUnit.kilometersPerHour;
  SpeedAccuracyMode _speedAccuracyMode = SpeedAccuracyMode.balanced;
  MapStyle _mapStyle = MapStyle.standard;
  RouteOverlay _routeOverlay = RouteOverlay.none;
  int _autoPauseReminderMinutes = 3;
  PositionDisplayFormat _positionDisplayFormat = PositionDisplayFormat.dms;
  PlaceResult? _destination;
  double _altitudeManualOffsetMeters = 0;
  SpeedDisplayStyle _speedDisplayStyle = SpeedDisplayStyle.digital;
  final Map<SpeedUnit, int> _speedScaleMax = {};
  UserProfile? _userProfile;
  StartGridColumns _startGridColumns = StartGridColumns.auto;
  StepCountMode _stepCountMode = StepCountMode.allDay;
  int _acceptedNavigationNoticeVersion = 0;
  DateTime? _navigationNoticeAcceptedAt;
  final Map<UserProfile, SpeedUnit> _profileUnits = {};
  final Map<UserProfile, List<SlotType>> _slots = {};

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

  /// NEU (README Abschnitt 54): Vom Nutzer auf der Kompass-Seite ermittelter
  /// Höhenversatz in Metern (0 = keiner). Wird auf die angezeigte und
  /// aufgezeichnete Höhe addiert (siehe AltitudeCorrection).
  double get altitudeManualOffsetMeters => _altitudeManualOffsetMeters;

  /// NEU (README Abschnitt 56): Auf der Start-Seite gewähltes Profil - null,
  /// solange noch keins gewählt wurde.
  UserProfile? get userProfile => _userProfile;

  /// NEU (README Abschnitt 70): true, sobald der Nutzer den Hinweis "keine
  /// Navigation" in der aktuellen Fassung ausdrücklich bestätigt hat. Solange
  /// es false ist, zeigt HomeShell den Hinweis bei jedem Start erneut.
  bool get navigationNoticeAccepted => _acceptedNavigationNoticeVersion >= currentNavigationNoticeVersion;

  /// Zeitpunkt der Bestätigung (null, solange nicht bestätigt).
  DateTime? get navigationNoticeAcceptedAt => _navigationNoticeAcceptedAt;

  /// NEU (README Abschnitt 57): Spaltenanzahl der Kacheln auf der
  /// Start-Seite (automatisch/1/2).
  StartGridColumns get startGridColumns => _startGridColumns;

  /// NEU (README Abschnitt 72): Zählweise des Schrittzählers (ganztägig oder
  /// nur während einer Track-Aufzeichnung). Standard: ganztägig.
  StepCountMode get stepCountMode => _stepCountMode;

  /// NEU (README Abschnitt 68): true im Profil "Segler" - die Auswertung von
  /// Tracks (Strecke, Tempo, Profil-Diagramme) erfolgt dann in Seemeilen (sm)
  /// und Knoten (kn) statt in km und km/h. Gilt für den gerade gewählten
  /// Stand, auch für zuvor in einem anderen Profil aufgezeichnete Tracks.
  bool get nauticalTrackUnits => _userProfile == UserProfile.sailor;

  /// Belegung der Slots der Start-Seite für [profile] - die vom Nutzer
  /// angepasste Liste, sonst die Standardbelegung des Profils.
  List<SlotType> slotsFor(UserProfile profile) => List.unmodifiable(_slots[profile] ?? profile.defaultSlots);

  /// Darstellung der Geschwindigkeit auf der Tacho-Seite (digital/analog).
  SpeedDisplayStyle get speedDisplayStyle => _speedDisplayStyle;

  /// Skalenende des analogen Tachos - je Einheit separat gespeichert.
  int speedScaleMax(SpeedUnit unit) => _speedScaleMax[unit] ?? SpeedScale.defaultFor(unit);

  /// true, solange das Seemarken-Overlay (OpenSeaMap) eingeblendet ist
  /// (siehe README Abschnitt 60). Nur noch eine abgeleitete Sicht auf
  /// [routeOverlay] - Seemarken sind seither ein Wert der Overlay-Auswahl;
  /// setzen lässt sich das nur über [setRouteOverlay].
  bool get mapNauticalMode => _routeOverlay == RouteOverlay.seamarks;

  /// NEU (siehe README Abschnitt 51): Gewählte Basiskarte (Standard,
  /// OpenTopoMap-R, Reit- und Wanderkarte). Das Overlay ([routeOverlay]) lässt
  /// sich über jede davon legen.
  MapStyle get mapStyle => _mapStyle;

  /// NEU (siehe README Abschnitt 52/60): Gewähltes Overlay über der Karte
  /// (Aus, Wanderrouten, Radrouten oder Seemarken), Standard: aus.
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

    // NEU (README Abschnitt 60): Der frühere, getrennte Seemarken-Schalter
    // ist jetzt ein Wert der Overlay-Auswahl. War er eingeschaltet und ist
    // sonst kein Overlay gewählt, bleiben die Seemarken sichtbar; war
    // zusätzlich ein Routen-Overlay gewählt, bleibt dieses (beides zugleich
    // gibt es nicht mehr). Der alte Schlüssel wird danach entfernt, sonst
    // würde er bei jedem Start erneut greifen.
    final legacyNautical = prefs.getBool(_legacyMapNauticalModeKey);
    if (legacyNautical != null) {
      if (legacyNautical && _routeOverlay == RouteOverlay.none) {
        _routeOverlay = RouteOverlay.seamarks;
        await prefs.setString(_routeOverlayKey, _routeOverlay.name);
      }
      await prefs.remove(_legacyMapNauticalModeKey);
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

    _acceptedNavigationNoticeVersion = prefs.getInt(_navigationNoticeVersionKey) ?? 0;
    final storedNoticeAt = prefs.getString(_navigationNoticeAcceptedAtKey);
    if (storedNoticeAt != null) {
      _navigationNoticeAcceptedAt = DateTime.tryParse(storedNoticeAt);
    }

    final storedGridColumns = prefs.getString(_startGridColumnsKey);
    if (storedGridColumns != null) {
      for (final columns in StartGridColumns.values) {
        if (columns.name == storedGridColumns) _startGridColumns = columns;
      }
    }

    final storedStepMode = prefs.getString(_stepCountModeKey);
    if (storedStepMode != null) {
      for (final mode in StepCountMode.values) {
        if (mode.name == storedStepMode) _stepCountMode = mode;
      }
    }

    final storedProfile = prefs.getString(_userProfileKey);
    if (storedProfile != null) {
      for (final profile in UserProfile.values) {
        if (profile.name == storedProfile) _userProfile = profile;
      }
    }
    for (final profile in UserProfile.values) {
      final storedUnit = prefs.getString('$_profileUnitKeyPrefix${profile.name}');
      if (storedUnit != null) {
        for (final unit in SpeedUnit.values) {
          if (unit.name == storedUnit) _profileUnits[profile] = unit;
        }
      }
      final storedSlots = prefs.getStringList('$_profileSlotsKeyPrefix${profile.name}');
      if (storedSlots != null) {
        final parsed = <SlotType>[];
        for (final name in storedSlots) {
          for (final type in SlotType.values) {
            if (type.name == name && !parsed.contains(type)) parsed.add(type);
          }
        }
        if (parsed.isNotEmpty) _slots[profile] = parsed;
      }
    }

    final storedAltitudeOffset = prefs.getDouble(_altitudeManualOffsetKey);
    if (storedAltitudeOffset != null && storedAltitudeOffset.isFinite) {
      _altitudeManualOffsetMeters = storedAltitudeOffset;
    }
    AltitudeCorrection.instance.manualOffsetMeters = _altitudeManualOffsetMeters;

    _campingBackcountry = prefs.getBool(_campingBackcountryKey) ?? false;
    final storedCampingUpdate = prefs.getString(_campingLastUpdateKey);
    if (storedCampingUpdate != null) {
      _campingLastUpdateAt = DateTime.tryParse(storedCampingUpdate);
    }
    notifyListeners();
  }

  /// Setzt den manuellen Höhenversatz (0 = zurücksetzen).
  Future<void> setAltitudeManualOffsetMeters(double meters) async {
    _altitudeManualOffsetMeters = meters;
    AltitudeCorrection.instance.manualOffsetMeters = meters;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (meters == 0) {
      await prefs.remove(_altitudeManualOffsetKey);
    } else {
      await prefs.setDouble(_altitudeManualOffsetKey, meters);
    }
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
    // NEU (README Abschnitt 56): Jedes Profil merkt sich seine zuletzt
    // gewählte Einheit.
    final profile = _userProfile;
    if (profile != null) _profileUnits[profile] = unit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedUnitKey, unit.name);
    if (profile != null) {
      await prefs.setString('$_profileUnitKeyPrefix${profile.name}', unit.name);
    }
  }

  /// NEU (README Abschnitt 56): Wählt das Profil der Start-Seite und stellt
  /// die dafür zuletzt verwendete (sonst die Standard-)Tempo-Einheit ein.
  /// Karte und Overlays bleiben dabei unberührt - dafür gibt es die
  /// Kartenvorwahl ([applyMapPreset]).
  Future<void> setUserProfile(UserProfile profile) async {
    _userProfile = profile;
    _speedUnit = _profileUnits[profile] ?? profile.defaultUnit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userProfileKey, profile.name);
    await prefs.setString(_speedUnitKey, _speedUnit.name);
  }

  /// Ändert die Slot-Belegung eines Profils (Einstellungen → Start, siehe
  /// README Abschnitt 57).
  Future<void> setSlotsFor(UserProfile profile, List<SlotType> slots) async {
    // Jede Anzeige höchstens einmal, Reihenfolge bleibt erhalten.
    final unique = <SlotType>[];
    for (final slot in slots) {
      if (!unique.contains(slot)) unique.add(slot);
    }
    _slots[profile] = unique;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_profileSlotsKeyPrefix${profile.name}',
      [for (final slot in unique) slot.name],
    );
  }

  /// Hält fest, dass der Nutzer den Hinweis "keine Navigation" (aktuelle
  /// Fassung) gelesen und verstanden hat - danach erscheint er nicht mehr.
  Future<void> acceptNavigationNotice() async {
    _acceptedNavigationNoticeVersion = currentNavigationNoticeVersion;
    _navigationNoticeAcceptedAt = DateTime.now();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_navigationNoticeVersionKey, currentNavigationNoticeVersion);
    await prefs.setString(_navigationNoticeAcceptedAtKey, _navigationNoticeAcceptedAt!.toIso8601String());
  }

  Future<void> setStartGridColumns(StartGridColumns columns) async {
    _startGridColumns = columns;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startGridColumnsKey, columns.name);
  }

  Future<void> setStepCountMode(StepCountMode mode) async {
    _stepCountMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stepCountModeKey, mode.name);
  }

  /// Stellt die Standardbelegung eines Profils wieder her.
  Future<void> resetSlotsFor(UserProfile profile) async {
    _slots.remove(profile);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_profileSlotsKeyPrefix${profile.name}');
  }

  /// true, wenn Basiskarte, Routen-Overlay und Seemarken bereits der
  /// Kartenvorwahl von [profile] entsprechen.
  bool isMapPresetActive(UserProfile profile) {
    final style = profile.mapStyle;
    if (style == null) return false;
    return _mapStyle == style && _routeOverlay == (profile.routeOverlay ?? RouteOverlay.none);
  }

  /// Setzt Basiskarte, Routen-Overlay und Seemarken auf die Kartenvorwahl
  /// von [profile] (gilt wie jede Kartenwahl für Track-Seite und
  /// Track-Detailansicht).
  Future<void> applyMapPreset(UserProfile profile) async {
    final style = profile.mapStyle;
    if (style == null) return;
    _mapStyle = style;
    _routeOverlay = profile.routeOverlay ?? RouteOverlay.none;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapStyleKey, _mapStyle.name);
    await prefs.setString(_routeOverlayKey, _routeOverlay.name);
  }

  Future<void> setSpeedAccuracyMode(SpeedAccuracyMode mode) async {
    _speedAccuracyMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedAccuracyModeKey, mode.name);
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

  // Schlüssel
  static const _campingBackcountryKey = 'campingBackcountry';
  static const _campingLastUpdateKey = 'campingLastUpdateAt';

// Felder
  bool _campingBackcountry = false;
  DateTime? _campingLastUpdateAt;

// Getter
  bool get campingEnabled => _routeOverlay == RouteOverlay.camping;
  bool get campingBackcountry => _campingBackcountry;
  DateTime? get campingLastUpdateAt => _campingLastUpdateAt;

// Setter
  Future<void> setCampingBackcountry(bool value) async {
    _campingBackcountry = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_campingBackcountryKey, value);
  }

  Future<void> setCampingLastUpdateAt(DateTime value) async {
    _campingLastUpdateAt = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_campingLastUpdateKey, value.toIso8601String());
  }
}
