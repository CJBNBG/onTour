/// Vom Nutzer in den Einstellungen (Unterreiter "Anzeige", siehe README
/// Abschnitt 25) wählbares Anzeigeformat für die aktuelle Position auf
/// der Start-Seite (Position-Kachel, siehe StartPage, util/coordinate_formatter.dart).
///
/// DMS war bislang die einzige, fest einprogrammierte Darstellung - je
/// nach Hintergrund (Seefahrt, klassisches Wandern, digitale
/// Kartenwerke/Vermessung) sind aber unterschiedliche Formate gebräuchlich
/// bzw. leichter mit anderem Kartenmaterial abzugleichen.
enum PositionDisplayFormat {
  dms(
    label: 'DMS (Grad, Minuten, Sekunden)',
    description: 'z. B. 52° 37\' 12,3" N - Standard, gebräuchlich in Nautik und Outdoor.',
  ),
  dmm(
    label: 'DMM (Grad, Dezimalminuten)',
    description: 'z. B. 52° 37,205\' N - verbreitet bei vielen handelsüblichen GPS-Geräten.',
  ),
  dd(
    label: 'DD (Dezimalgrad)',
    description: 'z. B. 52,62008° N - einfache Dezimaldarstellung ohne Minuten/Sekunden.',
  ),
  utm(
    label: 'UTM',
    description: 'z. B. 32U 599035 5674453 (Zone, Rechtswert, Hochwert) - '
        'gebräuchlich in Kartenwerk und Vermessung.',
  );

  final String label;
  final String description;

  const PositionDisplayFormat({required this.label, required this.description});
}
