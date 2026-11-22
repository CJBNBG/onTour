import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import '../models/camping_site.dart';

/// Fehler beim Aktualisieren der Camping-Daten mit lesbarer Meldung.
class CampingUpdateException implements Exception {
  final String message;
  const CampingUpdateException(this.message);

  @override
  String toString() => message;
}

/// Camping-/Stellplatzdaten (OpenCampingMap, OSM-Daten, ODbL): bevorzugt die
/// zuletzt heruntergeladene Datei im App-Ordner, sonst das mitgelieferte
/// Asset. Entpacken und Parsen laufen in einem Isolate.
class CampingDataService extends ChangeNotifier {
  CampingDataService._();
  static final CampingDataService instance = CampingDataService._();

  static const _asset = 'assets/camping/europe-camping.json.gz';
  static const _downloadUrl = 'https://github.com/CJBNBG/onTour/releases/download/camping-data/europe-camping.json.gz';
  static const _fileName = 'ontour_camping_data.json.gz';

  /// Datenstand des mitgelieferten Assets - bei jeder neuen Asset-Datei
  /// anpassen.
  static final DateTime _assetDataDate = DateTime(2026, 11, 21);

  /// Eine heruntergeladene Datei mit weniger Einträgen gilt als defekt.
  static const _minPlausibleCount = 10000;

  List<CampingSite>? _sites;
  Future<List<CampingSite>>? _loading;
  DateTime? _dataDate;

  bool get isLoaded => _sites != null;

  /// Datenstand als "TT.MM.JJJJ" (heruntergeladene Datei, sonst Asset).
  String get dataDateText {
    final d = _dataDate ?? _assetDataDate;
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Liest nur den Datenstand einer vorhandenen heruntergeladenen Datei
  /// (ohne zu parsen) - für die Anzeige in den Einstellungen.
  Future<void> loadDataDate() async {
    try {
      final file = await _localFile();
      if (await file.exists()) {
        _dataDate = await file.lastModified();
        notifyListeners();
      }
    } catch (_) {
      // Anzeige fällt dann auf den Asset-Stand zurück.
    }
  }

  Future<List<CampingSite>> load() => _loading ??= _load();

  Future<List<CampingSite>> _load() async {
    final List<CampingSite> result;
    final local = await _loadLocal();
    if (local != null) {
      result = local;
    } else {
      final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();
      result = await Isolate.run<List<CampingSite>>(() => _parse(bytes));
      _dataDate = _assetDataDate;
    }
    _sites = result;
    notifyListeners();
    return result;
  }

  /// Heruntergeladene Datei, falls vorhanden und brauchbar - sonst null
  /// (dann wird das Asset verwendet).
  Future<List<CampingSite>?> _loadLocal() async {
    try {
      final file = await _localFile();
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final parsed = await Isolate.run<List<CampingSite>>(() => _parse(bytes));
      if (parsed.length < _minPlausibleCount) return null;
      _dataDate = await file.lastModified();
      return parsed;
    } catch (_) {
      return null; // defekte Datei - Rückfall auf das Asset
    }
  }

  static List<CampingSite> _parse(Uint8List gz) {
    final list = jsonDecode(utf8.decode(gzip.decode(gz))) as List;
    return [for (final e in list) CampingSite.fromJson(e as Map<String, dynamic>)];
  }

  /// Lädt die aktuelle Datei vom Server (GitHub-Release), prüft sie und
  /// ersetzt die lokale Kopie. Wirft [CampingUpdateException] mit lesbarer
  /// Meldung; bei einem Fehler bleibt die bisherige Datei unverändert.
  Future<void> updateFromServer() async {
    final client = HttpClient()
      ..userAgent = 'onTour/1.0 (de.clausjbauer.ontour)'
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_downloadUrl)).timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw CampingUpdateException(
          'Die Datei ist nicht abrufbar (Status ${response.statusCode}).',
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(response).timeout(const Duration(minutes: 2));

      DateTime? modified;
      final header = response.headers.value(HttpHeaders.lastModifiedHeader);
      if (header != null) {
        try {
          modified = HttpDate.parse(header);
        } catch (_) {
          modified = null;
        }
      }

      final List<CampingSite> sites;
      try {
        sites = await Isolate.run<List<CampingSite>>(() => _parse(bytes));
      } catch (_) {
        throw const CampingUpdateException('Die heruntergeladene Datei ist unbrauchbar.');
      }
      if (sites.length < _minPlausibleCount) {
        throw const CampingUpdateException('Die heruntergeladene Datei ist unvollständig.');
      }

      final file = await _localFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      final date = modified ?? DateTime.now();
      try {
        await file.setLastModified(date);
      } catch (_) {
        // Dann gilt der Zeitpunkt des Downloads als Datenstand.
      }

      _sites = sites;
      _loading = Future.value(sites);
      _dataDate = await file.lastModified();
      notifyListeners();
    } on SocketException {
      throw const CampingUpdateException('Keine Internetverbindung.');
    } on TimeoutException {
      throw const CampingUpdateException('Der Server antwortet nicht (Zeitüberschreitung).');
    } on HandshakeException {
      throw const CampingUpdateException('Sichere Verbindung fehlgeschlagen.');
    } finally {
      client.close(force: true);
    }
  }

  /// Plätze im Kartenausschnitt, höchstens [limit] Stück.
  List<CampingSite> inBounds(
    LatLngBounds bounds, {
    required bool includeBackcountry,
    int limit = 400,
  }) {
    final sites = _sites;
    if (sites == null) return const [];
    final result = <CampingSite>[];
    for (final s in sites) {
      if (s.latitude < bounds.south || s.latitude > bounds.north) continue;
      if (s.longitude < bounds.west || s.longitude > bounds.east) continue;
      if (!includeBackcountry && s.category == CampingCategory.backcountry) continue;
      result.add(s);
      if (result.length >= limit) break;
    }
    return result;
  }
}
