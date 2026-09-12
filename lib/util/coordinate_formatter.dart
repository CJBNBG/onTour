import 'package:intl/intl.dart';

/// Formatiert geografische Koordinaten (Dezimalgrad, wie sie von
/// `geolocator`/GPS geliefert werden) im DMS-Format (Grad, Minuten,
/// Sekunden) - der im Outdoor-/Nautik-Bereich gebräuchlichen Darstellung,
/// im Gegensatz zu reinen Dezimalgraden. Verwendet auf der Kompass-Seite
/// für die aktuelle Position (siehe CompassPage).
class CoordinateFormatter {
  static final NumberFormat _secondsFormat = NumberFormat('00.0', 'de_DE');

  /// Formatiert einen Breitengrad, z. B. "52° 37' 12,3" N".
  static String formatLatitude(double latitude) =>
      _formatDms(latitude, positiveSuffix: 'N', negativeSuffix: 'S');

  /// Formatiert einen Längengrad, z. B. "9° 13' 45,6" O" - "O" statt "E"
  /// für Ost, passend zur deutschsprachigen Ausrichtung der App.
  static String formatLongitude(double longitude) =>
      _formatDms(longitude, positiveSuffix: 'O', negativeSuffix: 'W');

  /// Gemeinsame Umrechnung: Dezimalgrad -> Grad, (Bogen-)Minuten,
  /// (Bogen-)Sekunden. Das Vorzeichen des Dezimalwerts bestimmt die
  /// Himmelsrichtung (Suffix), der eigentliche Zahlenteil wird danach
  /// immer positiv (Betrag) dargestellt - so wie DMS-Koordinaten üblich
  /// angegeben werden (z. B. "S" statt einem negativen Breitengrad).
  static String _formatDms(
    double value, {
    required String positiveSuffix,
    required String negativeSuffix,
  }) {
    final suffix = value >= 0 ? positiveSuffix : negativeSuffix;
    final absolute = value.abs();
    final degrees = absolute.floor();
    final minutesTotal = (absolute - degrees) * 60;
    final minutes = minutesTotal.floor();
    final seconds = (minutesTotal - minutes) * 60;
    return "$degrees° $minutes' ${_secondsFormat.format(seconds)}\" $suffix";
  }
}
