import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/recorded_track.dart';

/// Persistiert aufgezeichnete Tracks als einzelne JSON-Dateien im
/// app-eigenen Dokumentenverzeichnis (Paket `path_provider`) - dadurch
/// bleiben gespeicherte Tracks auch nach einem App-Neustart erhalten, ohne
/// dass eine Datenbank nötig wäre. Für die in einer Alltags-App zu
/// erwartende Anzahl an Tracks (typischerweise einige Dutzend bis wenige
/// Hundert) ist das ein einfacher, robuster Ansatz - bewusst dieselbe
/// "Datei statt Datenbank"-Philosophie wie shared_preferences für die
/// übrigen Einstellungen dieses Projekts.
///
/// Bewusst zustandslos (keine gecachte Liste im Speicher): Jeder Aufruf
/// liest/schreibt direkt das Dateisystem - das macht die Klasse einfach
/// und robust gegenüber mehreren Instanzen (anders als
/// TrackRecordingService gibt es hier keinen Grund, eine einzelne
/// Instanz über Seitenwechsel hinweg am Leben zu halten).
class TrackStorageService {
  static const _folderName = 'tracks';

  Future<Directory> _tracksDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Speichert einen Track als `<id>.json` im Track-Verzeichnis.
  Future<void> save(RecordedTrack track) async {
    final dir = await _tracksDirectory();
    final file = File('${dir.path}/${track.id}.json');
    await file.writeAsString(jsonEncode(track.toJson()));
  }

  /// Lädt alle gespeicherten Tracks, neueste zuerst.
  Future<List<RecordedTrack>> loadAll() async {
    final dir = await _tracksDirectory();
    final entries = await dir.list().toList();
    final files = entries
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();

    final tracks = <RecordedTrack>[];
    for (final file in files) {
      try {
        final content = await file.readAsString();
        tracks.add(
          RecordedTrack.fromJson(jsonDecode(content) as Map<String, dynamic>),
        );
      } catch (_) {
        // Einzelne beschädigte/unlesbare Datei überspringen, statt die
        // gesamte Liste abzubrechen - so bleiben alle anderen, intakten
        // Tracks trotzdem nutzbar.
      }
    }
    tracks.sort((a, b) => b.startTime.compareTo(a.startTime));
    return tracks;
  }

  Future<void> delete(String id) async {
    final dir = await _tracksDirectory();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
