import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Liefert die Anzahl der für die aktuelle Positionsbestimmung
/// einbezogenen Satelliten - SOFERN die Plattform das überhaupt anbietet.
///
/// WICHTIG (Plattform-Einschränkung): Weder das `geolocator`-Paket noch
/// iOS/CoreLocation stellen eine Satellitenanzahl bereit - Apple gibt
/// diese Information grundsätzlich nicht an Apps weiter. Nur Android
/// erlaubt über die GNSS-Status-API (`LocationManager.registerGnssStatusCallback`,
/// API Level 24+) den Zugriff auf die Anzahl der aktuell für den Fix
/// verwendeten Satelliten. Diese Klasse kapselt daher einen eigenen,
/// nativen Android-Kanal (siehe native_android/MainActivity.kt in diesem
/// Projekt); auf iOS/Desktop/Web liefert der Stream einfach nichts, die UI
/// zeigt in diesem Fall konsequent "nicht verfügbar" an (siehe
/// SpeedPage), passend zur Formulierung "sofern die Daten über Satelliten
/// gewonnen werden" in den Anforderungen.
class SatelliteService {
  static const EventChannel _channel =
      EventChannel('ontour/gnss_satellite_count');

  Stream<int>? _stream;

  /// Stream mit der jeweils aktuellen Anzahl der für den Fix verwendeten
  /// Satelliten. Liefert auf Plattformen ohne Unterstützung (iOS, Desktop,
  /// Web, oder Android-Geräte mit zu altem API-Level) dauerhaft KEINE
  /// Werte (der Stream bleibt einfach leer) statt eines Fehlers - die UI
  /// unterscheidet "noch keine Daten" nicht extra von "nicht unterstützt",
  /// da für den Nutzer in beiden Fällen "nicht verfügbar" die richtige
  /// Anzeige ist.
  Stream<int> satelliteCountStream() {
    if (!Platform.isAndroid) {
      // Auf Nicht-Android-Plattformen bewusst kein Kanalaufruf: iOS besitzt
      // gar keinen entsprechenden nativen Code, ein Aufruf würde nur eine
      // (harmlose, aber unnötige) MissingPluginException verursachen.
      return const Stream.empty();
    }

    _stream ??= _channel.receiveBroadcastStream().map((event) => event as int).handleError(
      (Object error) {
        // Tritt z. B. auf, wenn die native Implementierung fehlt (Projekt
        // wurde ohne die bereitgestellte MainActivity.kt gebaut) oder das
        // Gerät kein GNSS besitzt - in diesem Fall einfach keine Werte
        // liefern, statt die App abstürzen zu lassen.
      },
    );
    return _stream!;
  }
}
