/// Vom Nutzer über den Schieberegler wählbare Anzeigeeinheit für die
/// Geschwindigkeit. Die Reihenfolge der Werte entspricht bewusst der
/// Reihenfolge auf dem Schieberegler (Index 0/1/2).
enum SpeedUnit {
  /// Meter pro Sekunde - die "rohe" Einheit, in der Geolocator Werte liefert.
  metersPerSecond('m/s'),

  /// Kilometer pro Stunde.
  kilometersPerHour('km/h'),

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
    }
  }
}
