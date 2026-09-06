import 'package:geolocator/geolocator.dart';

/// Vom Nutzer in den Einstellungen wählbare Kombination aus GPS-Genauigkeit
/// und Aktualisierungsrate für die Geschwindigkeitsmessung - ein direkter
/// Kompromiss zwischen Genauigkeit/Aktualität der Anzeige und Akkuverbrauch.
enum SpeedAccuracyMode {
  batterySaving(
    label: 'Akkusparend',
    description: 'Größere Messabstände und geringere GPS-Genauigkeit - '
        'schont den Akku spürbar, die Anzeige aktualisiert sich dafür '
        'seltener und etwas ungenauer.',
    accuracy: LocationAccuracy.medium,
    distanceFilterMeters: 15,
  ),

  balanced(
    label: 'Ausgewogen',
    description: 'Guter Kompromiss aus Aktualität und Akkuverbrauch - '
        'Standardeinstellung.',
    accuracy: LocationAccuracy.high,
    distanceFilterMeters: 1,
  ),

  maximum(
    label: 'Maximale Genauigkeit',
    description: 'Schnellstmögliche, genaueste Messung - kann den '
        'Akkuverbrauch deutlich erhöhen.',
    accuracy: LocationAccuracy.best,
    distanceFilterMeters: 0,
  );

  final String label;
  final String description;
  final LocationAccuracy accuracy;
  final int distanceFilterMeters;

  const SpeedAccuracyMode({
    required this.label,
    required this.description,
    required this.accuracy,
    required this.distanceFilterMeters,
  });

  LocationSettings toLocationSettings() => LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      );
}
