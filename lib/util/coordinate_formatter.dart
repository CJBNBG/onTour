import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/position_display_format.dart';

/// Formatiert geografische Koordinaten (Dezimalgrad, wie sie von
/// `geolocator`/GPS geliefert werden) in verschiedenen, in Outdoor-/
/// Nautik-/Vermessungs-Kreisen gebräuchlichen Darstellungen - wählbar über
/// [PositionDisplayFormat] auf der Einstellungsseite (Unterreiter
/// "Anzeige", siehe README Abschnitt 25). Verwendet auf der Kompass-Seite
/// für die aktuelle Position (siehe CompassPage).
class CoordinateFormatter {
  static final NumberFormat _dmsSecondsFormat = NumberFormat('00.0', 'de_DE');
  static final NumberFormat _dmmMinutesFormat = NumberFormat('00.000', 'de_DE');
  static final NumberFormat _ddDegreesFormat = NumberFormat('0.00000', 'de_DE');

  /// Liefert die für [format] passenden Anzeigezeilen für die übergebene
  /// Position - GENAU EINE Zeile bei [PositionDisplayFormat.utm] (Breite
  /// UND Länge fließen dort gemeinsam in eine einzige Positionsangabe
  /// ein), sonst ZWEI Zeilen (Breite, dann Länge) - siehe CompassPage,
  /// die diese Zeilen einfach der Reihe nach untereinander darstellt.
  static List<String> formatPosition(
    double latitude,
    double longitude,
    PositionDisplayFormat format,
  ) {
    switch (format) {
      case PositionDisplayFormat.dms:
        return [
          'Breite: ${_formatDms(latitude, positiveSuffix: 'N', negativeSuffix: 'S')}',
          'Länge: ${_formatDms(longitude, positiveSuffix: 'O', negativeSuffix: 'W')}',
        ];
      case PositionDisplayFormat.dmm:
        return [
          'Breite: ${_formatDmm(latitude, positiveSuffix: 'N', negativeSuffix: 'S')}',
          'Länge: ${_formatDmm(longitude, positiveSuffix: 'O', negativeSuffix: 'W')}',
        ];
      case PositionDisplayFormat.dd:
        return [
          'Breite: ${_formatDd(latitude, positiveSuffix: 'N', negativeSuffix: 'S')}',
          'Länge: ${_formatDd(longitude, positiveSuffix: 'O', negativeSuffix: 'W')}',
        ];
      case PositionDisplayFormat.utm:
        return ['Position: ${_formatUtm(latitude, longitude)}'];
    }
  }

  // ==== DMS (Grad/Minuten/Sekunden) ====

  /// Weiterhin öffentlich verfügbar (Breite/Länge einzeln im DMS-Format) -
  /// [formatPosition] ist für neue Verwendungen i. d. R. die bequemere
  /// Wahl, da sie automatisch das passende Format für alle vier Optionen
  /// liefert.
  static String formatLatitude(double latitude) =>
      _formatDms(latitude, positiveSuffix: 'N', negativeSuffix: 'S');

  static String formatLongitude(double longitude) =>
      _formatDms(longitude, positiveSuffix: 'O', negativeSuffix: 'W');

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
    return "$degrees° $minutes' ${_dmsSecondsFormat.format(seconds)}\" $suffix";
  }

  // ==== DMM (Grad/Dezimalminuten) ====

  static String _formatDmm(
    double value, {
    required String positiveSuffix,
    required String negativeSuffix,
  }) {
    final suffix = value >= 0 ? positiveSuffix : negativeSuffix;
    final absolute = value.abs();
    final degrees = absolute.floor();
    final minutes = (absolute - degrees) * 60;
    return "$degrees° ${_dmmMinutesFormat.format(minutes)}' $suffix";
  }

  // ==== DD (Dezimalgrad) ====

  static String _formatDd(
    double value, {
    required String positiveSuffix,
    required String negativeSuffix,
  }) {
    final suffix = value >= 0 ? positiveSuffix : negativeSuffix;
    return '${_ddDegreesFormat.format(value.abs())}° $suffix';
  }

  // ==== UTM (Universal Transverse Mercator) ====

  // WGS84-Ellipsoid-Parameter.
  static const double _a = 6378137.0; // große Halbachse in Metern
  static const double _f = 1 / 298.257223563; // Abplattung
  static const double _k0 = 0.9996; // Maßstabsfaktor auf dem Zentralmeridian

  /// Wandelt Breite/Länge (WGS84, Dezimalgrad) in eine UTM-Positionsangabe
  /// um (Zonennummer + Zonenbuchstabe, Rechtswert, Hochwert) - klassische
  /// Transversale-Merkator-Projektion nach den weit verbreiteten Formeln
  /// von Snyder (1987, "Map Projections - A Working Manual"). Genauigkeit
  /// im Bereich weniger Zentimeter für die hier relevanten mittleren
  /// Breiten - mehr als ausreichend gegenüber der GPS-eigenen Ungenauigkeit
  /// (siehe positionAccuracyMeters, i. d. R. mehrere Meter).
  ///
  /// BEWUSST NICHT BERÜCKSICHTIGT: die Sonderzonen für Norwegen/
  /// Spitzbergen (dort weichen einzelne UTM-Zonengrenzen von der sonst
  /// regelmäßigen 6°-Einteilung ab) - für den nautischen/Outdoor-
  /// Einsatzzweck dieser App an praktisch jedem anderen Ort der Erde ohne
  /// Belang; bei Bedarf jederzeit nachrüstbar.
  static String _formatUtm(double latitude, double longitude) {
    final e2 = _f * (2 - _f);
    final ePrime2 = e2 / (1 - e2);

    final zoneNumber = ((longitude + 180) / 6).floor() + 1;
    final zoneLetter = _utmZoneLetter(latitude);
    final lon0 = (zoneNumber - 1) * 6 - 180 + 3; // Zentralmeridian in Grad

    final phi = latitude * math.pi / 180;
    final lambda = longitude * math.pi / 180;
    final lambda0 = lon0 * math.pi / 180;

    final n = _a / math.sqrt(1 - e2 * math.pow(math.sin(phi), 2));
    final t = math.pow(math.tan(phi), 2);
    final c = ePrime2 * math.pow(math.cos(phi), 2);
    final aCoeff = math.cos(phi) * (lambda - lambda0);

    final m = _a *
        ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * phi -
            (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) * math.sin(2 * phi) +
            (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * math.sin(4 * phi) -
            (35 * e2 * e2 * e2 / 3072) * math.sin(6 * phi));

    final easting = _k0 *
            n *
            (aCoeff +
                (1 - t + c) * math.pow(aCoeff, 3) / 6 +
                (5 - 18 * t + t * t + 72 * c - 58 * ePrime2) * math.pow(aCoeff, 5) / 120) +
        500000.0;

    var northing = _k0 *
        (m +
            n *
                math.tan(phi) *
                (math.pow(aCoeff, 2) / 2 +
                    (5 - t + 9 * c + 4 * c * c) * math.pow(aCoeff, 4) / 24 +
                    (61 - 58 * t + t * t + 600 * c - 330 * ePrime2) * math.pow(aCoeff, 6) / 720));

    if (latitude < 0) {
      // Südhalbkugel: UTM zählt den Hochwert dort ab einem um 10.000 km
      // erhöhten Offset, damit er wie auf der Nordhalbkugel stets positiv
      // bleibt.
      northing += 10000000.0;
    }

    final eastingMeters = easting.round();
    final northingMeters = northing.round();
    return '$zoneNumber$zoneLetter $eastingMeters $northingMeters';
  }

  /// UTM-/MGRS-Breitenband-Buchstabe (C-X, ohne die leicht mit Ziffern zu
  /// verwechselnden Buchstaben I und O) für die übergebene geografische
  /// Breite - in 8°-Bändern von -80° bis 84° (das oberste Band X ist mit
  /// 12° etwas größer, hier vereinfachend mit abgedeckt).
  static String _utmZoneLetter(double latitude) {
    const letters = 'CDEFGHJKLMNPQRSTUVWX';
    if (latitude < -80 || latitude > 84) {
      // Außerhalb des eigentlichen UTM-Gültigkeitsbereichs (Polargebiete,
      // dort ist genau genommen das UPS-System gebräuchlich) - für diese
      // App ohne praktische Relevanz, daher nur ein neutraler Platzhalter
      // statt eines Absturzes.
      return 'Z';
    }
    var index = ((latitude + 80) / 8).floor();
    if (index < 0) index = 0;
    if (index > letters.length - 1) index = letters.length - 1;
    return letters[index];
  }
}
