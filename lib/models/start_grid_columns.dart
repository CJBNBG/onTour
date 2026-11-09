/// Spaltenanzahl der Kacheln auf der Start-Seite (siehe README Abschnitt
/// 57) - in den Einstellungen (Unterreiter "Start") wählbar.
enum StartGridColumns {
  auto(
    label: 'Automatisch',
    description: 'Eine Spalte auf schmalen Displays (Smartphone), zwei Spalten '
        'auf breiten (Tablet, Faltgerät) - Standard.',
  ),
  one(
    label: '1 Spalte',
    description: 'Immer eine Spalte: flache Kacheln mit Wert neben der '
        'Beschriftung, die Kompassrose bekommt mehr Platz.',
  ),
  two(
    label: '2 Spalten',
    description: 'Immer zwei Spalten: höhere Kacheln mit großem Wert.',
  );

  final String label;
  final String description;

  const StartGridColumns({required this.label, required this.description});

  /// Ab dieser Breite (logische Pixel) des Kachelbereichs wählt
  /// [StartGridColumns.auto] zwei Spalten.
  static const double autoTwoColumnMinWidth = 480;
}
