import 'package:intl/intl.dart';

import '../models/speed_unit.dart';

/// Formatiert einen Geschwindigkeitswert für die Anzeige.
///
/// GEÄNDERTE REGEL: Es wird jetzt IMMER mit genau einer Nachkommastelle
/// formatiert (frühere Regel "unterhalb von 10 km/h eine Nachkommastelle,
/// sonst keine" wurde aufgegeben). Die eine Nachkommastelle wird auf der
/// Tacho-Seite anschließend vom Vorkommateil abgetrennt und dort
/// hochgestellt, in ca. einem Drittel der Größe, direkt hinter der Zahl
/// dargestellt (siehe SpeedPage._buildSpeedNumber).
class SpeedFormatter {
  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'de_DE');

  /// [speedMetersPerSecond] bleibt als Parameter erhalten (unverändertes
  /// Aufruf-Interface), wird intern aber nicht mehr für eine
  /// Schwellenwert-Entscheidung benötigt (siehe Klassenkommentar).
  /// [displayValue] ist der bereits in die Zieleinheit umgerechnete,
  /// tatsächlich anzuzeigende Wert.
  static String format({
    required double speedMetersPerSecond,
    required double displayValue,
  }) {
    return _oneDecimal.format(displayValue);
  }

  /// Formatiert eine Genauigkeitsangabe (immer mit einer Nachkommastelle,
  /// unabhängig vom Geschwindigkeitswert, da es sich um eine deutlich
  /// kleiner dargestellte Zusatzangabe handelt).
  static String formatAccuracy(double? accuracyDisplayValue, SpeedUnit unit) {
    if (accuracyDisplayValue == null ||
        accuracyDisplayValue.isNaN ||
        accuracyDisplayValue < 0) {
      return 'Genauigkeit: unbekannt';
    }
    return 'Genauigkeit: ± ${_oneDecimal.format(accuracyDisplayValue)} ${unit.symbol}';
  }
}
