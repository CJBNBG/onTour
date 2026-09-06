import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Erkennt anhand des Beschleunigungssensors (ohne Erdanziehung, siehe
/// `userAccelerometerEventStream`), ob das Gerät gerade tatsächlich in
/// Ruhe liegt (z. B. auf einem Tisch) - unabhängig vom GPS-Signal.
///
/// HINTERGRUND: GPS-Positionen "wandern" durch Messungenauigkeiten leicht
/// (Mehrwegeausbreitung/Rauschen), auch wenn sich das Gerät gar nicht
/// bewegt - daraus errechnet Geolocator dann eine kleine, aber ungleich
/// Null schwankende Geschwindigkeit. Das lässt sich mit GPS-Daten allein
/// nicht zuverlässig unterscheiden. Der Beschleunigungssensor liefert
/// dafür ein unabhängiges zweites Signal: Liegt das Gerät wirklich still,
/// misst er (nach Abzug der Erdanziehung) nahezu exakt Null; jede
/// tatsächliche Bewegung/Erschütterung erzeugt einen messbaren Ausschlag.
///
/// EINSCHRÄNKUNG (bewusst in Kauf genommen): Bei sehr gleichmäßiger
/// Fahrt ohne jede Erschütterung (theoretisch denkbar, praktisch selten)
/// könnte der Beschleunigungssensor ebenfalls nahe Null liegen. Um eine
/// echte, schnelle Fahrt trotzdem niemals fälschlich auf 0 zu setzen,
/// wird die Stillstands-Korrektur in [SpeedPage] NUR dann angewendet,
/// wenn zusätzlich auch der GPS-Rohwert bereits selbst klein ist (siehe
/// dort) - der Bewegungssensor bestätigt in diesem Fall lediglich, dass
/// ein kleiner GPS-Wert wahrscheinlich Rauschen und keine echte
/// langsame Bewegung ist.
class MotionService {
  StreamSubscription<UserAccelerometerEvent>? _subscription;
  StreamController<bool>? _controller;

  /// Gleitendes Fenster der letzten Beschleunigungs-Beträge (m/s²) zur
  /// Glättung einzelner Ausreißer.
  final List<double> _recentMagnitudes = [];
  static const _windowSize = 15;

  /// ZWEI Schwellenwerte (m/s²) statt eines einzigen - eine sogenannte
  /// Hysterese bzw. ein Schmitt-Trigger: Um ÜBERHAUPT erst als "in Ruhe"
  /// zu gelten, muss der gemittelte Wert unter die NIEDRIGERE Schwelle
  /// fallen; um diesen Zustand wieder zu verlassen, muss er über die
  /// HÖHERE Schwelle steigen. Zwischen beiden Werten bleibt schlicht der
  /// zuletzt erkannte Zustand bestehen.
  ///
  /// GRUND: Mit nur einem einzigen Schwellenwert (frühere Version dieser
  /// Klasse) kippt die Erkennung bei einem gemittelten Wert, der genau um
  /// diesen einen Wert herum schwankt, in der Praxis sehr häufig hin und
  /// her - das ließ die Geschwindigkeitsanzeige auf der Tacho-Seite
  /// spürbar "flackern" (schneller, unruhiger Wechsel zwischen 0 und dem
  /// tatsächlichen GPS-Rohwert). Die Lücke zwischen beiden Schwellen
  /// schafft eine "tote Zone", in der ein einmal erreichter Zustand
  /// stabil bleibt, statt bei jeder kleinen Schwankung neu zu kippen.
  static const _enterStationaryThreshold = 0.10;
  static const _exitStationaryThreshold = 0.22;

  /// Zusätzlich muss eine Zustandsänderung über mehrere aufeinanderfolgende
  /// Messungen hinweg bestätigt werden (Entprellung/Debounce), bevor sie
  /// tatsächlich übernommen und nach außen gemeldet wird - so führt auch
  /// eine kurze, einzelne Erschütterung (z. B. ein Windstoß bei ansonsten
  /// ruhig liegendem Gerät) nicht sofort zu einem erneuten Kippen.
  static const _confirmationSamples = 5;

  /// Der zuletzt tatsächlich nach außen gemeldete (bereits durch
  /// Hysterese UND Entprellung bestätigte) Zustand.
  bool _stationary = false;

  /// Zustand, der sich gerade erst anzudeuten beginnt, aber noch nicht
  /// lange genug anhält, um übernommen zu werden - zusammen mit
  /// [_pendingCount] die Grundlage der Entprellung.
  bool? _pendingStationary;
  int _pendingCount = 0;

  /// Liefert fortlaufend, ob das Gerät aktuell (voraussichtlich) in Ruhe
  /// ist. Liefert auf Geräten/Plattformen ohne Beschleunigungssensor
  /// dauerhaft KEINE Werte (statt eines Fehlers) - [SpeedPage] verlässt
  /// sich in diesem Fall einfach ausschließlich auf die GPS-Rohdaten wie
  /// bisher.
  Stream<bool> isStationaryStream() {
    _controller ??= StreamController<bool>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening() {
    _subscription = userAccelerometerEventStream().listen(
      (event) {
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        _recentMagnitudes.add(magnitude);
        if (_recentMagnitudes.length > _windowSize) {
          _recentMagnitudes.removeAt(0);
        }
        final average =
            _recentMagnitudes.reduce((a, b) => a + b) / _recentMagnitudes.length;

        // Hysterese: Welcher Schwellenwert gilt, hängt vom AKTUELL
        // bestätigten Zustand ab - im Ruhezustand gilt die höhere
        // ("muss klar rausfahren, um als Bewegung zu zählen"), außerhalb
        // die niedrigere ("muss klar reinfallen, um als Ruhe zu zählen").
        final candidate = _stationary
            ? average < _exitStationaryThreshold
            : average < _enterStationaryThreshold;

        if (candidate == _stationary) {
          // Deckt sich mit dem bereits bestätigten Zustand - keine
          // Aenderung im Gange, Entprellung zuruecksetzen.
          _pendingStationary = null;
          _pendingCount = 0;
        } else if (_pendingStationary == candidate) {
          // Der neue Zustand deutet sich weiterhin an - einen Schritt
          // naeher an der Bestaetigung.
          _pendingCount++;
          if (_pendingCount >= _confirmationSamples) {
            _stationary = candidate;
            _pendingStationary = null;
            _pendingCount = 0;
          }
        } else {
          // Erstmaliges Andeuten eines Wechsels - Zaehlung neu beginnen.
          _pendingStationary = candidate;
          _pendingCount = 1;
        }

        _controller?.add(_stationary);
      },
      onError: (Object error) {
        // Kein Beschleunigungssensor vorhanden o. Ä. - einfach keine
        // weiteren Werte liefern, siehe Klassenkommentar.
      },
    );
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _recentMagnitudes.clear();
    _stationary = false;
    _pendingStationary = null;
    _pendingCount = 0;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller?.close();
    _subscription = null;
    _controller = null;
  }
}
