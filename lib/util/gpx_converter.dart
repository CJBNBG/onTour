import 'package:geolocator/geolocator.dart';
import 'package:xml/xml.dart';

import '../models/recorded_track.dart';
import '../models/track_point.dart';

/// Wandelt zwischen dem internen Track-Datenmodell und dem GPX-Format
/// (GPS Exchange Format, XML-basiert) um - für den Import/Export
/// aufgezeichneter Tracks (siehe README Abschnitt 20). GPX ist ein
/// offener, weit verbreiteter Standard, den u. a. Google Earth, Strava,
/// Komoot und OsmAnd lesen/schreiben können - dadurch lassen sich Tracks
/// aus dieser App an anderer Stelle weiterverwenden und umgekehrt dort
/// exportierte Tracks hier importieren.
///
/// Bewusst als reine, zustandslose Umwandlungslogik ohne jegliche
/// Datei-Ein-/Ausgabe gehalten (dafür ist `TrackImportExportService`
/// zuständig) - das hält diese Klasse einfach testbar und unabhängig
/// davon, woher der XML-Text kommt bzw. wohin er geschrieben wird.
class GpxConverter {
  /// Erzeugt aus einem [RecordedTrack] einen vollständigen, eigenständigen
  /// GPX-1.1-Dokumenttext (inkl. XML-Kopfzeile).
  static String encode(RecordedTrack track) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      nest: () {
        builder.attribute('version', '1.1');
        builder.attribute('creator', 'onTour');
        builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');

        builder.element(
          'metadata',
          nest: () {
            builder.element('name', nest: track.name);
            builder.element('time', nest: track.startTime.toUtc().toIso8601String());
          },
        );

        builder.element(
          'trk',
          nest: () {
            builder.element('name', nest: track.name);
            builder.element(
              'trkseg',
              nest: () {
                for (final point in track.points) {
                  builder.element(
                    'trkpt',
                    nest: () {
                      builder.attribute('lat', point.latitude.toString());
                      builder.attribute('lon', point.longitude.toString());
                      if (point.altitudeMeters != null) {
                        builder.element('ele', nest: point.altitudeMeters!.toStringAsFixed(1));
                      }
                      builder.element('time', nest: point.timestamp.toUtc().toIso8601String());
                    },
                  );
                }
              },
            );
          },
        );
      },
    );

    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  /// Liest einen GPX-Dokumenttext ein und liefert daraus einen
  /// vollständigen [RecordedTrack] (inkl. neu berechneter Distanz und
  /// Dauer). Die ID wird - konsistent mit `TrackRecordingService.stop()`
  /// - aus dem Startzeitpunkt des Tracks abgeleitet: Ein wiederholter
  /// Import derselben Datei überschreibt so denselben, bereits
  /// importierten Track, statt Duplikate anzulegen.
  ///
  /// [fallbackName] wird verwendet, wenn die GPX-Datei selbst keinen
  /// Namen enthält (weder `<trk><name>` noch `<metadata><name>`).
  ///
  /// Wirft eine [FormatException], wenn der Text kein gültiges XML ist
  /// oder keinen einzigen `<trkpt>` enthält (z. B. eine GPX-Datei, die
  /// nur einzelne Wegpunkte statt einer Strecke enthält - das deckt
  /// diese App bewusst nicht ab, siehe README).
  static RecordedTrack decode(String gpxContent, {required String fallbackName}) {
    final document = XmlDocument.parse(gpxContent);
    final gpxElement = document.getElement('gpx');
    if (gpxElement == null) {
      throw const FormatException('Kein gültiges GPX-Dokument (Wurzelelement <gpx> fehlt).');
    }

    // <trkpt> koennen laut GPX-Spezifikation in mehrere <trkseg>
    // (Segmente) unterteilt sein, z. B. wenn ein GPS-Geraet zwischenzeitlich
    // das Signal verlor. Diese App unterscheidet Segmente bewusst nicht
    // gesondert und behandelt alle <trkpt> als EINE durchgehende Strecke -
    // findAllElements durchsucht dafuer rekursiv das gesamte Dokument.
    final trkptElements = gpxElement.findAllElements('trkpt').toList();
    if (trkptElements.isEmpty) {
      throw const FormatException('Die GPX-Datei enthält keine Track-Punkte (<trkpt>).');
    }

    final points = <TrackPoint>[];
    DateTime? previousTimestamp;
    for (final trkpt in trkptElements) {
      final latText = trkpt.getAttribute('lat');
      final lonText = trkpt.getAttribute('lon');
      if (latText == null || lonText == null) continue; // ungueltiger Punkt, ueberspringen
      final lat = double.tryParse(latText);
      final lon = double.tryParse(lonText);
      if (lat == null || lon == null) continue;

      final eleText = trkpt.getElement('ele')?.innerText;
      final altitude = eleText != null ? double.tryParse(eleText) : null;

      final timeText = trkpt.getElement('time')?.innerText;
      final parsedTime = timeText != null ? DateTime.tryParse(timeText) : null;
      // Fehlt der Zeitstempel (in GPX optional), wird - statt abzubrechen -
      // einfach eine Sekunde nach dem vorherigen Punkt angenommen, damit
      // die zeitliche Reihenfolge und damit abgeleitete Werte wie die
      // Dauer weiterhin plausibel bleiben.
      final timestamp = parsedTime?.toLocal() ??
          (previousTimestamp ?? DateTime.now()).add(const Duration(seconds: 1));
      previousTimestamp = timestamp;

      points.add(TrackPoint(
        latitude: lat,
        longitude: lon,
        altitudeMeters: altitude,
        // GPX kennt kein Standardfeld für die Geschwindigkeit (siehe
        // README Abschnitt 20/29) - TrackProfileCalculator schätzt sie
        // bei Bedarf ersatzweise aus Distanz/Zeit zum vorherigen Punkt.
        speedMetersPerSecond: null,
        timestamp: timestamp,
      ));
    }

    if (points.isEmpty) {
      throw const FormatException('Die GPX-Datei enthält keine auswertbaren Track-Punkte.');
    }

    final name = gpxElement.getElement('trk')?.getElement('name')?.innerText ??
        gpxElement.getElement('metadata')?.getElement('name')?.innerText ??
        fallbackName;

    var distanceMeters = 0.0;
    for (var i = 1; i < points.length; i++) {
      distanceMeters += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }

    final startTime = points.first.timestamp;
    final endTime = points.last.timestamp;

    return RecordedTrack(
      id: startTime.millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? fallbackName : name.trim(),
      startTime: startTime,
      endTime: endTime,
      points: points,
      distanceMeters: distanceMeters,
      recordedDuration: endTime.difference(startTime),
    );
  }
}
