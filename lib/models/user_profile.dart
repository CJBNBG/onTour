import 'package:material_ui/material_ui.dart';

import 'map_style.dart';
import 'route_overlay.dart';
import 'speed_unit.dart';

/// Katalog aller Anzeigen ("Slots"), die auf der Start-Seite belegt werden
/// können (siehe README Abschnitt 56). Ein Profil ist nur eine Liste
/// dieser Bausteine - dieselbe Liste dient später auch dem frei
/// wählbaren Profil "Eigene" und dem Einstellungsbereich zur Anpassung.
///
/// "Schritte" (Schrittzähler, README Abschnitt 72) braucht die zusätzliche
/// Berechtigung ACTIVITY_RECOGNITION.
enum SlotType {
  speed(label: 'Tempo', icon: Icons.speed),
  steps(label: 'Schritte', icon: Icons.directions_walk),
  course(label: 'Kurs über Grund', icon: Icons.navigation),
  altitude(label: 'Höhe', icon: Icons.terrain),
  pressure(label: 'Luftdruck', icon: Icons.compress),
  position(label: 'Position', icon: Icons.my_location),
  compass(label: 'Kompass', icon: Icons.explore),
  mapPreset(label: 'Kartenvorwahl', icon: Icons.layers);

  final String label;
  final IconData icon;

  const SlotType({required this.label, required this.icon});
}

/// Zielgruppen-Profile der Start-Seite. Ein Profil legt fest, welche
/// Anzeigen in welcher Reihenfolge erscheinen, welche Einheit das Tempo
/// anfangs hat und welche Karte über die Kartenvorwahl gesetzt wird.
/// Alles davon lässt sich später einzeln ändern (Einheit auf der
/// Tacho-Seite, Slots in den Einstellungen).
enum UserProfile {
  hiker(
    label: 'Fußgänger / Wanderer',
    shortLabel: 'Wandern',
    icon: Icons.hiking,
    defaultUnit: SpeedUnit.metersPerSecond,
    defaultSlots: [
      SlotType.compass,
      SlotType.steps,
      SlotType.altitude,
      SlotType.pressure,
      SlotType.position,
      SlotType.mapPreset,
    ],
    mapStyle: MapStyle.hikingRiding,
    routeOverlay: RouteOverlay.hiking,
  ),

  sailor(
    label: 'Segler und Bootsführer',
    shortLabel: 'Segeln',
    icon: Icons.sailing,
    defaultUnit: SpeedUnit.knots,
    defaultSlots: [
      SlotType.compass,
      SlotType.course,
      SlotType.speed,
      SlotType.position,
      SlotType.pressure,
      SlotType.mapPreset,
    ],
    mapStyle: MapStyle.standard,
    routeOverlay: RouteOverlay.seamarks,
  ),

  cyclist(
    label: 'Fahrrad- / Motorradfahrer',
    shortLabel: 'Rad / Moto',
    icon: Icons.directions_bike,
    defaultUnit: SpeedUnit.kilometersPerHour,
    defaultSlots: [
      SlotType.speed,
      SlotType.altitude,
      SlotType.compass,
      SlotType.course,
      SlotType.pressure,
      SlotType.mapPreset,
    ],
    mapStyle: MapStyle.cyclOsm,
    routeOverlay: RouteOverlay.cycling,
  ),

  /// Früher "Wohnmobilist"/"Wohnmobil", seit README Abschnitt 62 "Reisen".
  /// Der Bezeichner `camper` bleibt bewusst unverändert, weil er als Name
  /// des gewählten Profils gespeichert wird (siehe AppPreferences) - eine
  /// Umbenennung würde die gespeicherte Wahl ungültig machen.
  camper(
    label: 'Wohnmobilisten und Camper',
    shortLabel: 'Reisen',
    icon: Icons.rv_hookup,
    defaultUnit: SpeedUnit.kilometersPerHour,
    defaultSlots: [
      SlotType.speed,
      SlotType.altitude,
      SlotType.compass,
      SlotType.position,
      SlotType.pressure,
      SlotType.mapPreset,
    ],
    mapStyle: MapStyle.topPlusOpen,
    routeOverlay: RouteOverlay.camping,
  ),

  /// Für alle, die sich in keiner Kategorie wiederfinden - Kartenvorwahl
  /// ist die Standardkarte ohne Overlay.
  custom(
    label: 'Eigene Auswahl',
    shortLabel: 'Eigene',
    // Bewusst NICHT Icons.tune: Dieses Symbol steht auf der Start-Seite
    // schon für "Höhe kalibrieren" in der Höhen-Kachel (README Abschnitt 67).
    icon: Icons.person,
    defaultUnit: SpeedUnit.kilometersPerHour,
    defaultSlots: [
      SlotType.speed,
      SlotType.course,
      SlotType.altitude,
      SlotType.position,
      SlotType.pressure,
      SlotType.mapPreset,
    ],
    mapStyle: MapStyle.standard,
  );

  final String label;

  /// Kurzbezeichnung für die schmale Profil-Leiste.
  final String shortLabel;
  final IconData icon;

  /// Anfangseinheit des Tempos, solange der Nutzer für dieses Profil noch
  /// keine andere gewählt hat.
  final SpeedUnit defaultUnit;

  /// Standardbelegung der Slots (Reihenfolge = Anzeigereihenfolge).
  final List<SlotType> defaultSlots;

  /// Kartenvorwahl des Profils - null = das Profil setzt keine Karte.
  final MapStyle? mapStyle;

  /// Overlay der Kartenvorwahl (Wander-/Radrouten oder Seemarken) - null =
  /// keins.
  final RouteOverlay? routeOverlay;

  const UserProfile({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.defaultUnit,
    required this.defaultSlots,
    this.mapStyle,
    this.routeOverlay,
  });

  /// Lesbare Beschreibung der Kartenvorwahl für die Kachel auf der
  /// Start-Seite, z. B. "Reit- und Wanderkarte · Wanderrouten".
  String get mapPresetDescription {
    final style = mapStyle;
    if (style == null) return 'Keine Kartenvorwahl';
    final parts = <String>[style.label];
    final overlay = routeOverlay;
    if (overlay != null && overlay.isActive) parts.add(overlay.label);
    return parts.join(' · ');
  }
}
