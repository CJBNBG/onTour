import 'package:intl/intl.dart';

/// Formatiert Strecke, Dauer und Zeitstempel eines aufgezeichneten Tracks
/// für die Anzeige.
class TrackFormatter {
  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'de_DE');
  static final NumberFormat _noDecimal = NumberFormat('0', 'de_DE');
  static final DateFormat _dateTimeFormat =
      DateFormat('dd.MM.yyyy, HH:mm', 'de_DE');

  /// Unterhalb von 1 km in Metern (ohne Nachkommastelle), sonst in km mit
  /// einer Nachkommastelle - analog zur Nachkommastellen-Logik von
  /// SpeedFormatter, hier aber anhand der absoluten Distanz entschieden.
  static String formatDistance(double meters) {
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
  static String formatAverageSpeed(double meters, Duration duration) {
    if (duration.inSeconds <= 0) return '- km/h';
    final kmh = (meters / 1000) / (duration.inSeconds / 3600);
    return '${_oneDecimal.format(kmh)} km/h';
  }

  static String formatDateTime(DateTime dateTime) =>
      _dateTimeFormat.format(dateTime);

  /// Vorschlag für einen Standard-Tracknamen, falls der Nutzer keinen
  /// eigenen einträgt.
  static String suggestName(DateTime startTime) =>
      'Track vom ${formatDateTime(startTime)}';
}
