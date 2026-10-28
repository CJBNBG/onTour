/// Ein gefundener bzw. markierter Ort - Ergebnis der Ortssuche
/// (PlaceSearchService) oder eines langen Drückens auf die Karte; dient als
/// Ziel auf der Track-Seite (siehe README Abschnitt 50).
class PlaceResult {
  /// Kurzer Name (z. B. "Kiel" oder "Marktplatz") - für Marker/Kartenanzeige.
  final String name;

  /// Vollständige Bezeichnung (z. B. "Kiel, Schleswig-Holstein, Deutschland")
  /// - für die Ergebnisliste.
  final String displayName;

  final double latitude;
  final double longitude;

  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'lat': latitude,
        'lon': longitude,
      };

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
        name: json['name'] as String,
        displayName: (json['displayName'] as String?) ?? json['name'] as String,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
      );
}
