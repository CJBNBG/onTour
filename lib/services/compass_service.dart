import 'package:flutter_compass/flutter_compass.dart';

import '../models/compass_reading.dart';

/// Kapselt den Zugriff auf den Magnetkompass des Geräts (Paket
/// `flutter_compass`).
class CompassService {
  /// true, wenn das Gerät über einen Kompass-Sensor verfügt. Sollte vor
  /// dem Abonnieren von [readingStream] geprüft werden (manche Geräte,
  /// insbesondere reine WLAN-Tablets, besitzen keinen Magnetometer).
  bool get isSupported => FlutterCompass.events != null;

  Stream<CompassReading> readingStream() {
    final events = FlutterCompass.events;
    if (events == null) return const Stream.empty();

    return events
        .where((event) => event.heading != null)
        .map((event) => CompassReading(
              headingDegrees: _normalizeDegrees(event.heading!),
              accuracyDegrees: event.accuracy,
            ));
  }

  /// Normalisiert einen Winkel auf den Bereich [0, 360). Laut Dokumentation
  /// von `flutter_compass` liefert `heading` zwar bereits ausschließlich
  /// Werte von 0-360, in der Praxis wurden auf manchen Geräten aber
  /// vereinzelt knapp negative Werte beobachtet (z. B. -0,4° statt 359,6°) -
  /// diese Normalisierung stellt unabhängig davon sicher, dass NIE ein
  /// negativer Wert angezeigt wird.
  static double _normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
