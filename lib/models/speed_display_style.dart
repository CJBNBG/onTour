/// Darstellung der Geschwindigkeit auf der Tacho-Seite - in den
/// Einstellungen (Unterreiter "Anzeige") wählbar.
enum SpeedDisplayStyle {
  digital(
    label: 'Digital',
    description: 'Rote Sieben-Segment-Anzeige (Standard).',
  ),
  analog(
    label: 'Analog',
    description: 'Rundinstrument mit Zeiger und wählbarem Skalenende.',
  );

  final String label;
  final String description;

  const SpeedDisplayStyle({required this.label, required this.description});
}
