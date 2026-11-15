import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';

/// Vom Nutzer in den Einstellungen wählbare Kombination aus GPS-Genauigkeit
/// und Aktualisierungsrate für die Geschwindigkeitsmessung - ein direkter
/// Kompromiss zwischen Genauigkeit/Aktualität der Anzeige und Akkuverbrauch.
///
/// NEU (siehe README Abschnitt 37): Wird seither NICHT mehr ausschließlich
/// auf der Tacho-Seite verwendet, sondern dient jetzt auch als
/// einheitliches Vokabular für eine kleine Genauigkeits-Anzeige
/// (`widgets/accuracy_badge.dart`) auf Kompass- und Track-Seite - dort
/// jeweils passend zur dort tatsächlich fest verwendeten
/// `LocationAccuracy` ermittelt (siehe [fromLocationAccuracy]), NICHT
/// über diese Einstellung selbst steuerbar (die gilt nach wie vor nur
/// für die Tacho-Seite, siehe Abschnitt 4).
enum SpeedAccuracyMode {
  batterySaving(
    label: 'Akkusparend',
    description: 'Größere Messabstände und geringere GPS-Genauigkeit - '
        'schont den Akku spürbar, die Anzeige aktualisiert sich dafür '
        'seltener und etwas ungenauer.',
    accuracy: LocationAccuracy.medium,
    distanceFilterMeters: 15,
    color: Colors.amber,
  ),

  balanced(
    label: 'Ausgewogen',
    description: 'Guter Kompromiss aus Aktualität und Akkuverbrauch - '
        'Standardeinstellung.',
    accuracy: LocationAccuracy.high,
    distanceFilterMeters: 1,
    color: Colors.blue,
  ),

  maximum(
    label: 'Maximale Genauigkeit',
    description: 'Schnellstmögliche, genaueste Messung - kann den '
        'Akkuverbrauch deutlich erhöhen.',
    accuracy: LocationAccuracy.best,
    distanceFilterMeters: 0,
    color: Colors.green,
  );

  final String label;
  final String description;
  final LocationAccuracy accuracy;
  final int distanceFilterMeters;

  /// NEU (siehe README Abschnitt 37): Farbe für die kleine
  /// Genauigkeits-Anzeige - bewusst nicht themenabhängig (feste
  /// Material-Farben statt `ColorScheme`-Werten), damit die Bedeutung
  /// (Akkusparend/Ausgewogen/Maximal) auf allen Seiten und unabhängig
  /// vom Anzeigemodus (Hell/Dunkel) sofort wiedererkennbar bleibt - drei
  /// klar unterscheidbare, für diese Bedeutung intuitive Farben (gelb ~
  /// "sparsam", blau ~ "neutral/Standard", grün ~ "volle Leistung").
  final Color color;

  const SpeedAccuracyMode({
    required this.label,
    required this.description,
    required this.accuracy,
    required this.distanceFilterMeters,
    required this.color,
  });

  LocationSettings toLocationSettings() => LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      );

  /// NEU (siehe README Abschnitt 37): Liefert die zu einer (ggf. fest
  /// einprogrammierten, nicht vom Nutzer wählbaren) [LocationAccuracy]
  /// passende Stufe - für die Genauigkeits-Anzeige auf Kompass- und
  /// Track-Seite, deren zugrunde liegende Standort-Dienste
  /// (AltitudeService bzw. TrackRecordingService) jeweils eine eigene,
  /// feste Genauigkeit verwenden, unabhängig von dieser Einstellung
  /// (siehe Abschnitt 10/19). `orElse` liefert [balanced] als neutralen
  /// Rückfallwert, falls jemals eine [LocationAccuracy] verwendet würde,
  /// die keiner der drei Stufen entspricht (aktuell kommt das nicht vor).
  static SpeedAccuracyMode fromLocationAccuracy(LocationAccuracy accuracy) {
    return SpeedAccuracyMode.values.firstWhere(
      (mode) => mode.accuracy == accuracy,
      orElse: () => SpeedAccuracyMode.balanced,
    );
  }
}
