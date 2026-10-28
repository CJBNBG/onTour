import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Einfacher, rein Dart-seitiger Diagnose-Logger (siehe README Abschnitt
/// 33/34) - schreibt Zeitstempel plus Ereignistext in eine Textdatei im
/// app-eigenen Speicher, über ganz normale Dart-Datei-Schreibvorgänge.
///
/// WICHTIG - ERSETZT einen vorherigen, VOLLSTÄNDIG VERWORFENEN Ansatz
/// (siehe Abschnitt 31/32): Ursprünglich wurde dafür `logcat` als
/// nativer Kindprozess gestartet - das führte auf einem echten Gerät
/// (Samsung S23 Ultra) bereits beim bloßen Versuch, diesen Prozess zu
/// starten, zu einem sofortigen, nicht abfangbaren Absturz beim
/// App-Start (auch nach Verlagerung auf einen Hintergrund-Thread und
/// Abfangen von `Throwable` statt nur `Exception` - vermutlich eine
/// harte SELinux-Verweigerung, die unterhalb der Java-Exception-Ebene
/// greift). Dieser hier verwendete Ansatz kommt bewusst OHNE jeden
/// nativen Prozessaufruf aus - nur ganz gewöhnliche Datei-I/O über
/// `dart:io`, wie sie auch `TrackStorageService` oder der Checkpoint-
/// Mechanismus in `TrackRecordingService` bereits verwenden.
///
/// EINSCHRÄNKUNG (bewusst in Kauf genommen): Ein ECHTER nativer Absturz
/// (z. B. ein Kotlin-seitiger Fehler innerhalb des geolocator-Plugins)
/// würde weiterhin NICHT hier erfasst, da der Dart-Isolate in diesem
/// Fall selbst nicht mehr weiterläuft, um den Absturz noch protokollieren
/// zu können - dafür bliebe weiterhin nur ein per PC angeschlossenes
/// `adb logcat`. Erfasst werden aber alle Dart-seitig sichtbaren
/// Ereignisse (siehe Aufrufstellen in TrackRecordingService und
/// HomeShell) - das deckt den in Abschnitt 30.4 beschriebenen,
/// wahrscheinlicheren Fall (Aufzeichnung "friert" unbemerkt ein, OHNE
/// dass die App komplett abstürzt) bereits gut ab.
class DiagnosticLogService {
  DiagnosticLogService._();

  /// Einzige Instanz - bewusst als einfaches Singleton statt über
  /// Dependency Injection gereicht, da mehrere, voneinander unabhängige
  /// Stellen (TrackRecordingService, HomeShell, InfoPage) unkompliziert
  /// in dieselbe Datei schreiben bzw. sie exportieren können sollen,
  /// ohne dass jede von ihnen extra eine Instanz durchgereicht bekommen
  /// müsste.
  static final DiagnosticLogService instance = DiagnosticLogService._();

  static const _fileName = 'ontour_diagnose.log';

  /// Ab dieser Dateigröße wird der bisherige Inhalt verworfen und neu
  /// begonnen - verhindert unbegrenztes Wachstum bei sehr langen
  /// Testsitzungen (z. B. mehrstündige Wanderungen), auf Kosten der
  /// ältesten Zeilen.
  static const _maxBytes = 2 * 1024 * 1024;

  File? _cachedFile;
  bool _clearedThisSession = false;

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final file = File('${documents.path}/$_fileName');
    _cachedFile = file;
    return file;
  }

  /// Schreibt eine Zeile mit Zeitstempel ans Ende der Diagnose-Datei -
  /// bewusst komplett "fire and forget" (Aufrufer wartet nicht auf den
  /// Abschluss): Ein Fehlschlag (z. B. kurzzeitig voller Speicher) wird
  /// verschluckt, da Logging niemals die eigentliche Funktion der App
  /// beeinträchtigen darf - siehe Aufrufstellen, die diese Methode
  /// entsprechend nie awaiten.
  ///
  /// FEHLERKORREKTUR (siehe README Abschnitt 35): Läuft jetzt NUR in
  /// Nicht-Release-Builds (`!kReleaseMode`, also `flutter run` sowie
  /// Debug-/Profile-Builds) - `kReleaseMode` ist eine von Flutter selbst
  /// zur Kompilierzeit gesetzte Konstante, die für `flutter build
  /// appbundle`/`flutter build apk --release` (also auch für einen für
  /// den Play Store hochgeladenen internen Test) `true` ergibt. Ohne
  /// diese Prüfung hätte die Protokollierung unbemerkt auch bei echten
  /// Play-Store-Testern/Nutzern mitgelaufen - der ursprünglich mit der
  /// nativen Logcat-Variante (Abschnitt 31) verfolgten Absicht (Diagnose
  /// ausschließlich in Test-Builds) entsprechend nachgezogen, jetzt aber
  /// rein Dart-seitig und ohne jede Gradle-/native Abhängigkeit.
  Future<void> log(String message) async {
    if (kReleaseMode) return;
    try {
      final file = await _file();

      // Frischer Start bei jedem App-Start (Prozessstart) - analog zum
      // Vorgänger-Ansatz, damit sich eine Datei nicht über viele
      // App-Starts hinweg unbegrenzt aufsummiert.
      if (!_clearedThisSession) {
        if (await file.exists()) await file.delete();
        _clearedThisSession = true;
      }

      if (await file.exists() && await file.length() > _maxBytes) {
        await file.delete();
      }

      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('$timestamp  $message\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Siehe Methodenkommentar - Logging ist ein reiner Komfort-Zusatz.
    }
  }

  /// true, wenn eine nicht-leere Diagnose-Datei existiert - in einem
  /// Release-Build immer `false` (siehe [log]), damit der zugehörige
  /// Export-Button auf der Info-Seite dort gar nicht erst erscheint.
  Future<bool> hasLog() async {
    if (kReleaseMode) return false;
    final file = await _file();
    if (!await file.exists()) return false;
    return await file.length() > 0;
  }

  /// Öffnet den nativen "Teilen"-Dialog mit der aktuellen Diagnose-Datei
  /// - z. B. per Mail oder Messenger an den Entwickler weiterzugeben.
  /// Zusätzliche Absicherung ("defense in depth") zu [hasLog]: Auch wenn
  /// der Export-Button dank [hasLog] in einem Release-Build gar nicht
  /// erst angezeigt wird, bricht diese Methode sicherheitshalber
  /// ebenfalls sofort ab, falls sie dennoch aufgerufen würde.
  Future<void> shareLog() async {
    if (kReleaseMode) return;
    final file = await _file();
    if (!await file.exists()) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'onTour Diagnose-Protokoll',
        subject: 'onTour Diagnose-Protokoll',
      ),
    );
  }
}
