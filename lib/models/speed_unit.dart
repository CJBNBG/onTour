/// Vom Nutzer über den Schieberegler wählbare Anzeigeeinheit für die
/// Geschwindigkeit. Die Reihenfolge der Werte entspricht bewusst der
/// Reihenfolge der Einheitenwahl (Index 0-3: m/s, km/h, mph, kn).
enum SpeedUnit {
  /// Meter pro Sekunde - die "rohe" Einheit, in der Geolocator Werte liefert.
  metersPerSecond('m/s'),

  /// Kilometer pro Stunde.
  kilometersPerHour('km/h'),

  /// Meilen pro Stunde (Statute Miles, 1609,344 m) - v. a. im
  /// angloamerikanischen Straßenverkehr üblich.
  milesPerHour('mph'),

  /// Knoten (Seemeilen pro Stunde) - u. a. in der Schiff-/Luftfahrt üblich.
  knots('kn');

  /// Kurzes Einheiten-Symbol für die Anzeige.
  final String symbol;

  const SpeedUnit(this.symbol);

  /// Rechnet einen in m/s gegebenen Wert in diese Einheit um.
  double fromMetersPerSecond(double metersPerSecond) {
    switch (this) {
      case SpeedUnit.metersPerSecond:
        return metersPerSecond;
      case SpeedUnit.kilometersPerHour:
        return metersPerSecond * 3.6;
      case SpeedUnit.knots:
        // 1 m/s = 1,9438444924574 kn (exakter Umrechnungsfaktor über die
        // international festgelegte Seemeile von 1852 m).
        return metersPerSecond * 1.9438444924574;
      case SpeedUnit.milesPerHour:
        // 1 m/s = 2,2369362920544 mph (1 mile = 1609,344 m exakt).
        return metersPerSecond * 2.2369362920544;
    }
  }
}
