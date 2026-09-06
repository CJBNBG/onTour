import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recorded_track.dart';
import '../util/gpx_converter.dart';
import '../util/track_formatter.dart';

/// Kapselt Export (als GPX-Datei über den nativen Android-"Teilen"-Dialog)
/// und Import (über einen Datei-Auswahl-Dialog) aufgezeichneter Tracks -
/// siehe README Abschnitt 20 für den Hintergrund. Nutzt intern
/// [GpxConverter] für die eigentliche Formatumwandlung und kümmert sich
/// nur um die Datei-Ein-/Ausgabe drumherum.
class TrackImportExportService {
  /// Schreibt den Track als GPX-Datei in das app-eigene, temporäre
  /// Verzeichnis (Paket `path_provider`) und öffnet anschließend den
  /// nativen "Teilen"-Dialog (Paket `share_plus`) - darüber kann die
  /// Datei z. B. in der Dateien-App gespeichert, per Mail verschickt oder
  /// in eine andere GPS-App importiert werden. Bewusst KEIN direktes
  /// Schreiben in einen für den Nutzer sichtbaren Ordner (dafür wäre unter
  /// aktuellem Android die Storage Access Framework-Zustimmung des
  /// Nutzers nötig) - der Teilen-Dialog deckt "irgendwo dauerhaft
  /// speichern" bereits mit ab (z. B. per "In Dateien speichern").
  Future<void> exportTrack(RecordedTrack track) async {
    final gpxContent = GpxConverter.encode(track);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${_fileNameFor(track)}');
    await file.writeAsString(gpxContent);

    await Share.shareXFiles([XFile(file.path)], text: track.name);
  }

  /// Öffnet den nativen Datei-Auswahl-Dialog (Paket `file_picker`,
  /// beschränkt auf `.gpx`-Dateien) und liefert bei erfolgreicher Auswahl
  /// den daraus gelesenen Track zurück - null, wenn der Nutzer den Dialog
  /// abgebrochen hat. Speichert den Track selbst NICHT - das obliegt der
  /// aufrufenden Seite (siehe TrackPage), damit diese z. B. nach dem
  /// Import noch die Liste neu laden oder eine Bestätigung anzeigen kann.
  ///
  /// Wirft eine [FormatException] weiter nach oben, wenn die gewählte
  /// Datei kein auswertbares GPX enthält (siehe GpxConverter.decode) - die
  /// aufrufende Seite fängt das ab und zeigt eine verständliche
  /// Fehlermeldung an.
  Future<RecordedTrack?> pickAndImportTrack() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null; // sollte auf Android praktisch nicht vorkommen

    final content = await File(path).readAsString();
    final fallbackName = TrackFormatter.suggestName(DateTime.now());
    return GpxConverter.decode(content, fallbackName: fallbackName);
  }

  /// Dateiname für den Export - unerlaubte Zeichen im Tracknamen werden
  /// durch Unterstriche ersetzt, damit auf allen Zielsystemen (auch nach
  /// dem Teilen z. B. per Mail-Anhang) ein gültiger Dateiname entsteht.
  String _fileNameFor(RecordedTrack track) {
    final sanitized = track.name.replaceAll(RegExp(r'[^A-Za-z0-9äöüÄÖÜß _-]'), '_');
    return '$sanitized.gpx';
  }
}
