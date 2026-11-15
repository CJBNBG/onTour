import 'package:intl/intl.dart';

/// Formatiert Strecke, Dauer und Zeitstempel eines aufgezeichneten Tracks
/// für die Anzeige.
///
/// NEU (README Abschnitt 68): Mit `nautical: true` (Profil "Segler") werden
/// Strecken in Seemeilen (sm) und Geschwindigkeiten in Knoten (kn)
/// ausgegeben statt in km und km/h.
class TrackFormatter {
  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'de_DE');
  static final NumberFormat _twoDecimals = NumberFormat('0.00', 'de_DE');
  static final NumberFormat _noDecimal = NumberFormat('0', 'de_DE');

  /// 1 Seemeile = 1852 m (international festgelegt).
  static const double metersPerNauticalMile = 1852;

  /// 1 m/s in Knoten (über die Seemeile von 1852 m).
  static const double knotsPerMeterPerSecond = 1.9438444924574;
  static final DateFormat _dateTimeFormat =
      DateFormat('dd.MM.yyyy, HH:mm', 'de_DE');

  /// Unterhalb von 1 km in Metern (ohne Nachkommastelle), sonst in km mit
  /// einer Nachkommastelle - analog zur Nachkommastellen-Logik von
  /// SpeedFormatter, hier aber anhand der absoluten Distanz entschieden.
  ///
  /// Nautisch: unter 100 m in Metern, darüber in Seemeilen - unter 1 sm
  /// mit zwei, ab 1 sm mit einer Nachkommastelle.
  static String formatDistance(double meters, {bool nautical = false}) {
    if (nautical) {
      if (meters < 100) return '${_noDecimal.format(meters)} m';
      final nm = meters / metersPerNauticalMile;
      return '${(nm < 1 ? _twoDecimals : _oneDecimal).format(nm)} sm';
    }
    if (meters < 1000) {
      return '${_noDecimal.format(meters)} m';
    }
    return '${_oneDecimal.format(meters / 1000)} km';
  }

  /// Dauer als H:MM:SS bzw. MM:SS, wenn unter einer Stunde.
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  /// Durchschnittsgeschwindigkeit in km/h aus Strecke und Dauer - '-',
  /// solange die Dauer noch bei null Sekunden liegt (z. B. direkt nach
  /// dem Start).
  static String formatAverageSpeed(double meters, Duration duration, {bool nautical = false}) {
    if (duration.inSeconds <= 0) return nautical ? '- kn' : '- km/h';
    return formatSpeed(meters / duration.inSeconds, nautical: nautical);
  }

  /// Geschwindigkeit aus m/s in km/h bzw. (nautisch) Knoten, eine
  /// Nachkommastelle.
  static String formatSpeed(double metersPerSecond, {bool nautical = false}) {
    final value = nautical
        ? metersPerSecond * knotsPerMeterPerSecond
        : metersPerSecond * 3.6;
    return '${_oneDecimal.format(value)} ${nautical ? 'kn' : 'km/h'}';
  }

  static String formatDateTime(DateTime dateTime) =>
      _dateTimeFormat.format(dateTime);

  /// Vorschlag für einen Standard-Tracknamen, falls der Nutzer keinen
  /// eigenen einträgt.
  static String suggestName(DateTime startTime) =>
      'Track vom ${formatDateTime(startTime)}';
}
