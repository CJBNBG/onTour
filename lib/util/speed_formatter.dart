import 'package:intl/intl.dart';

import '../models/speed_unit.dart';

/// Formatiert einen Geschwindigkeitswert für die Anzeige.
///
/// ANNAHME zur Nachkommastellen-Regel: Die Vorgabe "unterhalb von 10km/h
/// eine Nachkommastelle, sonst keine" nennt die Schwelle explizit in
/// km/h - unabhängig davon, in welcher Einheit gerade angezeigt wird. Die
/// Umsetzung prüft daher immer den km/h-Wert der tatsächlichen
/// Geschwindigkeit, um zu entscheiden, ob mit oder ohne Nachkommastelle
/// formatiert wird, formatiert die ausgegebene Zahl aber in der vom
/// Nutzer gewählten Einheit (z. B. auch ein sehr kleiner kn- oder m/s-Wert
/// bekommt eine Nachkommastelle, wenn die zugrunde liegende Geschwindigkeit
/// unter 10 km/h liegt).
class SpeedFormatter {
  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'de_DE');
  static final NumberFormat _noDecimal = NumberFormat('0', 'de_DE');

  /// [speedMetersPerSecond] wird für die Schwellenwert-Entscheidung
  /// benötigt, [displayValue] ist der bereits in die Zieleinheit
  /// umgerechnete, tatsächlich anzuzeigende Wert.
  static String format({
    required double speedMetersPerSecond,
    required double displayValue,
  }) {
    final speedKmh = SpeedUnit.kilometersPerHour.fromMetersPerSecond(speedMetersPerSecond);
    final format = speedKmh < 10 ? _oneDecimal : _noDecimal;
    return format.format(displayValue);
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
