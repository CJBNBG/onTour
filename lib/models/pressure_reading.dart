/// Einstufung der Luftdruckentwicklung über 3 Stunden - angelehnt an die
/// in der Meteorologie/Seefahrt gebräuchlichen Tendenz-Stufen (hPa pro
/// 3 Stunden). Schwellen: 1,0 / 3,5 / 6,0 hPa.
///
/// Die Schwelle für "gleichbleibend" liegt bewusst bei ±1,0 hPa (statt
/// einer feineren Stufe), da Smartphone-Barometer selbst über Stunden
/// um einige Zehntel hPa driften können (Temperatur, Bauteil-Toleranz).
enum PressureTrendCategory {
  veryRapidlyFalling('sehr schnell fallend', '↓↓'),
  rapidlyFalling('schnell fallend', '↓'),
  falling('fallend', '↘'),
  steady('gleichbleibend', '→'),
  rising('steigend', '↗'),
  rapidlyRising('schnell steigend', '↑'),
  veryRapidlyRising('sehr schnell steigend', '↑↑');

  final String label;
  final String arrow;

  const PressureTrendCategory(this.label, this.arrow);

  /// Ordnet eine Druckänderung in hPa pro 3 Stunden einer Stufe zu.
  static PressureTrendCategory fromChangePer3h(double change) {
    if (change <= -6.0) return veryRapidlyFalling;
    if (change <= -3.5) return rapidlyFalling;
    if (change <= -1.0) return falling;
    if (change < 1.0) return steady;
    if (change < 3.5) return rising;
    if (change < 6.0) return rapidlyRising;
    return veryRapidlyRising;
  }
}

/// Aktueller Luftdruck samt (sofern genug Daten vorliegen) 3-Stunden-Trend,
/// wie ihn der [PressureTrendService] liefert (siehe README Abschnitt 47).
///
/// WICHTIG: [hPa] ist der am Gerät GEMESSENE Luftdruck (Stationsdruck), NICHT
/// der auf Meereshöhe umgerechnete Druck aus Wetterberichten - beide
/// unterscheiden sich pro 100 m Höhe um rund 12 hPa.
class PressureReading {
  /// Geglätteter Stationsdruck in hPa.
  final double hPa;

  /// Druckänderung hochgerechnet auf 3 Stunden (hPa/3 h, Ausgleichsgerade
  /// über das verfügbare Zeitfenster). null, solange weniger als
  /// [PressureTrendService.minTrendBasis] Verlauf vorliegt.
  final double? changePer3hHPa;

  /// Zeitspanne, über die der Trend tatsächlich bestimmt wurde (max.
  /// 3 Stunden). null, wenn [changePer3hHPa] null ist.
  final Duration? trendBasis;

  /// true, wenn sich die bekannte Höhe im Trend-Zeitfenster um mehr als
  /// 15 m geändert hat - der Trend vermischt dann Wetter- und
  /// Höhenänderung und ist unzuverlässig.
  final bool altitudeChanged;

  const PressureReading({
    required this.hPa,
    required this.changePer3hHPa,
    required this.trendBasis,
    required this.altitudeChanged,
  });

  PressureTrendCategory? get category {
    final change = changePer3hHPa;
    return change == null ? null : PressureTrendCategory.fromChangePer3h(change);
  }
}
