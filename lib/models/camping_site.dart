import 'place_result.dart';

enum CampingCategory { standard, caravan, backcountry }

class CampingSite {
  final String id; // z. B. "node/123" oder "way/456" (OSM)
  final double latitude;
  final double longitude;
  final CampingCategory category;
  final String? name, operator, fee, tents, caravans, nudism;
  final String? internetAccess, internetFee, dumpStation, website, phone;

  const CampingSite({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.name,
    this.operator,
    this.fee,
    this.tents,
    this.caravans,
    this.nudism,
    this.internetAccess,
    this.internetFee,
    this.dumpStation,
    this.website,
    this.phone,
  });

  factory CampingSite.fromJson(Map<String, dynamic> j) {
    String? s(String key) {
      final v = j[key];
      return v == null ? null : '$v';
    }

    final category = switch (s('category')) {
      'caravan' => CampingCategory.caravan,
      'backcountry' => CampingCategory.backcountry,
      _ => CampingCategory.standard,
    };
    return CampingSite(
      id: j['i'] as String,
      latitude: (j['y'] as num).toDouble(),
      longitude: (j['x'] as num).toDouble(),
      category: category,
      name: s('name:de') ?? s('name') ?? s('name:en'),
      operator: s('operator'),
      fee: s('fee'),
      tents: s('tents'),
      caravans: s('caravans'),
      nudism: s('nudism'),
      internetAccess: s('internet_access'),
      internetFee: s('internet_access:fee'),
      dumpStation: s('sanitary_dump_station'),
      website: s('contact:website'),
      phone: s('contact:phone'),
    );
  }

  String get categoryLabel => switch (category) {
        CampingCategory.standard => 'Campingplatz',
        CampingCategory.caravan => 'Stellplatz',
        CampingCategory.backcountry => 'Wildcampen',
      };

  String get displayName => name ?? categoryLabel;

  /// Link, der den Eintrag in OpenCampingMap aufschlägt (Karte zentriert,
  /// Objekt ausgewählt). Für andere Objektarten als node/way nur die Position.
  String get openCampingMapUrl {
    final lat = latitude.toStringAsFixed(5);
    final lon = longitude.toStringAsFixed(5);
    final isObject = id.startsWith('node/') || id.startsWith('way/');
    return 'https://opencampingmap.org/#17/$lat/$lon/0/1/bef${isObject ? '/$id' : ''}';
  }

  PlaceResult toPlaceResult() => PlaceResult(
        name: displayName,
        displayName: '$displayName ($categoryLabel)',
        latitude: latitude,
        longitude: longitude,
      );
}
