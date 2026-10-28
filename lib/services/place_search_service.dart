import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/place_result.dart';

/// Fehler der Ortssuche mit einer für den Nutzer lesbaren Meldung.
class PlaceSearchException implements Exception {
  final String message;
  const PlaceSearchException(this.message);

  @override
  String toString() => message;
}

/// Sucht Orte über den kostenlosen Geocoding-Dienst Nominatim von
/// OpenStreetMap (siehe README Abschnitt 50) - passend zum Rest der App
/// (OpenStreetMap-Kacheln), ohne API-Key und ohne zusätzliches
/// Paket (nur `dart:io`).
///
/// NUTZUNGSBEDINGUNGEN von Nominatim (öffentlicher Server), die hier
/// bewusst eingehalten werden: höchstens 1 Anfrage pro Sekunde
/// ([_minRequestInterval]), ein aussagekräftiger User-Agent, KEINE
/// Suche-während-der-Eingabe (Autovervollständigung ist ausdrücklich
/// untersagt - gesucht wird nur auf ausdrücklichen Befehl des Nutzers),
/// und eine Quellenangabe in der Oberfläche. Bei starker Nutzung wäre
/// ein eigener oder kommerzieller Geocoding-Dienst nötig.
class PlaceSearchService {
  static const _host = 'nominatim.openstreetmap.org';
  static const _userAgent = 'onTour/1.0 (de.clausjbauer.ontour)';
  static const Duration _minRequestInterval = Duration(seconds: 1);
  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxResults = 8;

  DateTime? _lastRequestAt;

  /// Liefert bis zu [_maxResults] Treffer zu [query] - leere Liste, wenn
  /// nichts gefunden wurde (oder die Anfrage zu kurz ist). Wirft eine
  /// [PlaceSearchException] mit verständlicher Meldung bei Netz- oder
  /// Dienstfehlern.
  Future<List<PlaceResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    // Mindestabstand zwischen zwei Anfragen einhalten.
    final last = _lastRequestAt;
    if (last != null) {
      final wait = _minRequestInterval - DateTime.now().difference(last);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();

    final uri = Uri.https(_host, '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '$_maxResults',
      'accept-language': 'de',
    });

    final client = HttpClient()
      ..userAgent = _userAgent
      ..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw PlaceSearchException(
          'Der Suchdienst ist derzeit nicht erreichbar (Status ${response.statusCode}).',
        );
      }
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const PlaceSearchException('Unerwartete Antwort des Suchdiensts.');
      }
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) ..._parse(item),
      ];
    } on SocketException {
      throw const PlaceSearchException('Keine Internetverbindung.');
    } on TimeoutException {
      throw const PlaceSearchException('Der Suchdienst antwortet nicht (Zeitüberschreitung).');
    } on HandshakeException {
      throw const PlaceSearchException('Sichere Verbindung zum Suchdienst fehlgeschlagen.');
    } on FormatException {
      throw const PlaceSearchException('Unerwartete Antwort des Suchdiensts.');
    } finally {
      client.close(force: true);
    }
  }

  /// Wandelt einen Nominatim-Eintrag in ein [PlaceResult] - leere Liste
  /// bei unbrauchbaren Einträgen (fehlende/ungültige Koordinaten).
  static List<PlaceResult> _parse(Map<String, dynamic> item) {
    final lat = double.tryParse('${item['lat']}');
    final lon = double.tryParse('${item['lon']}');
    if (lat == null || lon == null) return const [];

    final displayName = (item['display_name'] as String?)?.trim() ?? '';
    var name = (item['name'] as String?)?.trim() ?? '';
    if (name.isEmpty && displayName.isNotEmpty) {
      name = displayName.split(',').first.trim();
    }
    if (name.isEmpty) name = 'Ziel';

    return [
      PlaceResult(
        name: name,
        displayName: displayName.isEmpty ? name : displayName,
        latitude: lat,
        longitude: lon,
      ),
    ];
  }
}
