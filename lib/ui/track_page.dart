import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/place_result.dart';
import '../models/recorded_track.dart';
import '../models/speed_accuracy_mode.dart';
import '../services/app_preferences.dart';
import '../services/place_search_service.dart';
import '../services/track_import_export_service.dart';
import '../services/track_recording_service.dart';
import '../services/track_storage_service.dart';
import '../util/track_formatter.dart';
import '../util/track_profile_calculator.dart';
import 'track_detail_page.dart';
import 'widgets/accuracy_badge.dart';
import 'widgets/map_tile_layers.dart';
import 'widgets/measurement_pulse_indicator.dart';
import 'widgets/map_legend_button.dart';
import 'widgets/map_style_button.dart';
import 'widgets/north_lock_button.dart';
import 'widgets/place_search_sheet.dart';
import 'widgets/track_profile_charts.dart';

/// Ergebnis des "Aufzeichnung beenden"-Dialogs (siehe _handleStop).
enum _StopDialogAction { cancel, discard, save }

/// Seite zur Aufzeichnung eines Tracks: Live-Karte (dieselbe umschaltbare
/// Landkarte/Seekarte samt Nordausrichtungs-Fixierung wie zuvor die
/// eigenständige Kartenseite, siehe widgets/map_tile_layers.dart,
/// widgets/nautical_mode_button.dart und widgets/north_lock_button.dart)
/// mit dem bisher zurückgelegten Streckenverlauf, Start-/Pause-/
/// Beenden-Steuerung sowie eine Liste bereits gespeicherter Tracks (zum
/// Anzeigen in TrackDetailPage oder Löschen).
///
/// WICHTIG: Der [recordingService] wird - anders als die Services der
/// übrigen Seiten - NICHT hier erzeugt, sondern von HomeShell übergeben
/// und überlebt dadurch Tab-Wechsel (siehe Kommentar in
/// TrackRecordingService und HomeShell). Diese Seite selbst wird beim
/// Tab-Wechsel weiterhin ganz normal disposed/neu erzeugt - das betrifft
/// dann aber nur ihren eigenen UI-Zustand (Kartenposition, geladene
/// Liste), nicht die laufende Aufzeichnung.
///
/// NEU (siehe README Abschnitt 29): Zwei Unterreiter "Karte" und
/// "Details" (analog zur Einstellungsseite, siehe Abschnitt 24) - "Karte"
/// entspricht dem bisherigen alleinigen Seiteninhalt, "Details" zeigt
/// Momentanwerte (Geschwindigkeit, Kurs, Höhenänderung seit Start,
/// Steigung/Gefälle) sowie vier Profil-Diagramme der laufenden
/// Aufzeichnung (siehe widgets/track_profile_charts.dart). Die Start-/
/// Pause-/Beenden-Steuerung bleibt bewusst AUSSERHALB der Unterreiter,
/// unterhalb von beiden gleichermaßen sichtbar - der Nutzer soll die
/// Aufzeichnung auch pausieren/beenden können, während er gerade die
/// Details betrachtet, nicht nur auf der Karte.
class TrackPage extends StatefulWidget {
  final TrackRecordingService recordingService;
  final AppPreferences preferences;

  const TrackPage({
    super.key,
    required this.recordingService,
    required this.preferences,
  });

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  final TrackStorageService _storageService = TrackStorageService();
  final TrackImportExportService _importExportService = TrackImportExportService();
  final MapController _mapController = MapController();
  final PlaceSearchService _placeSearchService = PlaceSearchService();

  /// NEU (README Abschnitt 50): Solange gesetzt und in der Zukunft, führt
  /// die Karte der laufenden Aufzeichnung NICHT automatisch zur eigenen
  /// Position - sonst würde sie sofort wieder vom gerade angezeigten Ziel
  /// wegspringen.
  DateTime? _followPausedUntil;

  StreamSubscription<void>? _recordingSubscription;
  StreamSubscription<MapEvent>? _mapEventSubscription;
  Timer? _uiTicker;

  TrackLocationAvailability _availability = TrackLocationAvailability.checking;
  List<RecordedTrack> _savedTracks = [];
  bool _loadingSavedTracks = true;

  /// Einmalig ermittelte Position für die Kartenmitte, solange noch keine
  /// eigenen Aufzeichnungspunkte vorliegen (siehe _initialize).
  LatLng? _initialCenter;
  bool _mapReady = false;

  /// Aktuelle Kartendrehung in Grad - fuer die Ausrichtung des Pfeils im
  /// Nord-Steuerelement (siehe NorthLockButton).
  double _rotationDegrees = 0;

  /// true, solange die Nordausrichtung "eingerastet" ist - siehe
  /// NorthLockButton fuer die genaue Bedeutung. Bewusst NICHT persistiert
  /// (siehe README Abschnitt 5), startet also bei jedem Seitenaufruf neu
  /// im freien, drehbaren Ausgangszustand.
  bool _northLocked = true;

  /// NEU (siehe README Abschnitt 37): Letzte bekannte Punktezahl - dient
  /// [_recordingSubscription] dazu, einen NEUEN Punkt (statt irgendeine
  /// der vielen anderen Änderungen, die `updates` ebenfalls auslöst,
  /// z. B. Pause/Fortsetzen) zu erkennen.
  int _lastKnownPointCount = 0;

  /// Wird bei jedem NEUEN Track-Punkt erhöht - dient
  /// MeasurementPulseIndicator als Auslöser für den kurzen optischen
  /// Impuls.
  int _measurementTick = 0;

  @override
  void initState() {
    super.initState();
    _recordingSubscription = widget.recordingService.updates.listen((_) {
      if (!mounted) return;
      final currentPointCount = widget.recordingService.points.length;
      if (currentPointCount > _lastKnownPointCount) {
        _measurementTick++;
      }
      _lastKnownPointCount = currentPointCount;
      setState(() {});
      _syncWakelock();
      _followLiveRecording();
    });
    _mapEventSubscription = _mapController.mapEventStream.listen((event) {
      if (!mounted) return;
      setState(() => _rotationDegrees = event.camera.rotation);
    });
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Nur fuer die staendig weiterlaufende Dauer-Anzeige waehrend einer
      // aktiven Aufzeichnung - sonst kein unnoetiges Neuzeichnen.
      if (!mounted) return;
      if (widget.recordingService.state == RecordingState.recording) {
        setState(() {});
      }
    });
    _initialize();
    _loadSavedTracks();
    _syncWakelock();
    _checkForRecoverableCheckpoint();
  }

  /// NEU (Fehlerkorrektur, siehe README): Prüft beim Öffnen der Track-Seite,
  /// ob eine Checkpoint-Datei einer vorherigen, nicht regulär beendeten
  /// Aufzeichnung existiert (siehe TrackRecordingService) - z. B. weil der
  /// App-Prozess während einer laufenden Aufzeichnung unerwartet beendet
  /// wurde. Nur relevant, wenn GERADE KEINE Aufzeichnung läuft (`idle`) -
  /// läuft bereits wieder eine (die App wurde normal neu gestartet,
  /// TrackRecordingService lebt als Singleton in HomeShell unverändert
  /// weiter, siehe dort), ist der Checkpoint ohnehin nur ein veralteter
  /// Überrest EINER FRÜHEREN, bereits laufenden Aufzeichnung und wird beim
  /// nächsten regulären Beenden automatisch entfernt.
  Future<void> _checkForRecoverableCheckpoint() async {
    if (widget.recordingService.state != RecordingState.idle) return;
    final recovered = await widget.recordingService.checkForRecoverableCheckpoint();
    if (recovered == null || !mounted) return;

    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        // Bewusst normale Text-Widgets statt AutoHyphenatingText - siehe
        // ausführliche Begründung bei den übrigen AlertDialogs dieser
        // Seite (_handleStop): OverflowBar/intrinsische
        // Breitenberechnung verträgt sich nicht mit AutoHyphenatingText.
        title: const Text('Nicht beendete Aufzeichnung gefunden'),
        content: Text(
          'Es wurde eine Track-Aufzeichnung vom '
          '${TrackFormatter.formatDateTime(recovered.startTime)} gefunden, '
          'die offenbar nicht regulär beendet wurde (z. B. durch ein '
          'unerwartetes Beenden der App). Sie enthält '
          '${recovered.points.length} Punkte '
          '(${TrackFormatter.formatDistance(recovered.distanceMeters)}). '
          'Möchtest du sie als Track speichern?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Verwerfen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      await _storageService.save(recovered);
      await _loadSavedTracks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Track "${recovered.name}" wiederhergestellt.')),
        );
      }
    }
    await widget.recordingService.discardRecoverableCheckpoint();
  }

  Future<void> _initialize() async {
    // Laeuft bereits eine Aufzeichnung (z. B. nach Rueckkehr von einem
    // anderen Tab), war die Berechtigung offensichtlich schon vorhanden -
    // die erneute Pruefung kann dann entfallen.
    if (widget.recordingService.state != RecordingState.idle) {
      setState(() => _availability = TrackLocationAvailability.ready);
      return;
    }

    final availability = await widget.recordingService.checkAvailability();
    if (!mounted) return;
    setState(() => _availability = availability);
    if (availability != TrackLocationAvailability.ready) return;

    // NEU (siehe README Abschnitt 36): Bittet um die Benachrichtigungs-
    // Berechtigung (ab Android 13 nötig, siehe Manifest-Eintrag
    // POST_NOTIFICATIONS in Abschnitt 2) - ohne sie kann geolocator keine
    // sichtbare Foreground-Service-Benachrichtigung anzeigen, sobald eine
    // Aufzeichnung gestartet wird (siehe TrackRecordingService, Abschnitt
    // 19). Wird bereits beim Öffnen der Track-Seite abgefragt (nicht erst
    // beim tatsächlichen Start der Aufzeichnung), damit Standort- und
    // Benachrichtigungs-Berechtigung im selben Arbeitsschritt erledigt
    // werden, statt den Nutzer erst beim eigentlichen Start zusätzlich zu
    // unterbrechen. Ein Ablehnen wird bewusst NICHT blockierend behandelt
    // (kein eigener Hinweisbildschirm wie bei der Standort-Berechtigung) -
    // die Aufzeichnung funktioniert auch ohne sichtbare Benachrichtigung
    // technisch weiter, nur eben ohne die in Abschnitt 19 beschriebenen
    // Vorteile für den Hintergrundbetrieb.
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Einmalige Positionsbestimmung nur fuer die Start-Kartenmitte, solange
    // noch nicht aufgezeichnet wird - bewusst KEIN Dauer-Stream, um nicht
    // ohne Grund GPS zu verbrauchen, bevor der Nutzer tatsaechlich auf
    // "Aufzeichnung starten" tippt.
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _initialCenter = LatLng(position.latitude, position.longitude));
    } catch (_) {
      // Keine Position ermittelbar (z. B. Innenraum ohne Fix) - die Karte
      // zeigt dann einfach erst ab dem ersten Aufzeichnungspunkt etwas an.
    }
  }

  Future<void> _loadSavedTracks() async {
    setState(() => _loadingSavedTracks = true);
    final tracks = await _storageService.loadAll();
    if (!mounted) return;
    setState(() {
      _savedTracks = tracks;
      _loadingSavedTracks = false;
    });
  }

  void _syncWakelock() {
    // Bildschirm bleibt nur waehrend AKTIVER Aufzeichnung wach - analog zur
    // Tacho-/Kompass-Seite, die den Bildschirm ebenfalls nur waehrend
    // tatsaechlicher Nutzung wachhalten (siehe README).
    if (widget.recordingService.state == RecordingState.recording) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Verschiebt die Karte auf den zuletzt aufgezeichneten Punkt - nur
  /// waehrend einer laufenden Aufzeichnung.
  void _followLiveRecording() {
    if (!_mapReady) return;
    final pausedUntil = _followPausedUntil;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) return;
    final points = widget.recordingService.points;
    if (points.isEmpty) return;
    final last = points.last;
    _mapController.move(LatLng(last.latitude, last.longitude), _mapController.camera.zoom);
  }

  Future<void> _openTrackDetail(RecordedTrack track) async {
    Navigator.of(context).pop(); // Bottom Sheet schliessen
    final shouldReload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrackDetailPage(track: track, preferences: widget.preferences),
      ),
    );
    if (shouldReload == true) {
      await _loadSavedTracks();
    }
  }

  Future<void> _handleStart() async {
    // NEU (siehe README Abschnitt 38): start() ist jetzt async (kann bei
    // sehr kurz zuvor beendeter Aufzeichnung intern kurz warten, siehe
    // TrackRecordingService._minRestartGap) - deshalb hier awaited.
    await widget.recordingService.start();
  }

  Future<void> _handlePause() async {
    await widget.recordingService.pause();
  }

  Future<void> _handleResume() async {
    widget.recordingService.resume();
  }

  Future<void> _handleStop() async {
    final suggested = TrackFormatter.suggestName(
      widget.recordingService.startTime ?? DateTime.now(),
    );
    final controller = TextEditingController(text: suggested);

    try {
      final action = await showDialog<_StopDialogAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          // scrollable:true sorgt dafür, dass der Dialog auch dann noch
          // bedienbar bleibt (Inhalt wird bei Bedarf scrollbar), wenn die
          // Bildschirmtastatur viel vertikalen Platz einnimmt - siehe auch
          // die bewusst entfernte autofocus-Eigenschaft direkt darunter.
          scrollable: true,
          // WICHTIG (Fehlerkorrektur): title bewusst als normales Text-
          // Widget statt AutoHyphenatingText. Bei scrollable: true packt
          // Flutter title UND content GEMEINSAM in einen scrollbaren
          // Bereich, der Teil derselben intrinsischen
          // Breitenberechnung ist wie unten die Aktionsleiste (siehe
          // Kommentar dort) - ein alleiniges Korrigieren der actions
          // reichte deshalb nicht aus, der Fehler trat weiterhin auf,
          // solange der title noch AutoHyphenatingText verwendete.
          title: const Text('Aufzeichnung beenden'),
          content: TextField(
            controller: controller,
            // WICHTIG: bewusst KEIN autofocus. Mit autofocus öffnet sich
            // beim Erscheinen des Dialogs sofort die Tastatur, die auf
            // vielen (v. a. kleineren) Bildschirmen die Aktions-Buttons
            // dieses Dialogs ("Weiter aufzeichnen"/"Verwerfen"/"Speichern")
            // nach unten aus dem sichtbaren Bereich schiebt oder verdeckt -
            // der Dialog liess sich dann faktisch nicht mehr bedienen, was
            // wie ein nicht funktionierendes "Beenden" wirkte. Der Name
            // kann bei Bedarf weiterhin ganz normal per Antippen des Felds
            // geändert werden, dann öffnet sich die Tastatur gezielt erst
            // in diesem Moment.
            decoration: const InputDecoration(labelText: 'Name des Tracks'),
          ),
          actions: [
            // WICHTIG: Bewusst normale Text-Widgets statt
            // AutoHyphenatingText - AlertDialog legt seine actions über
            // ein OverflowBar an, das bei zu wenig Platz (hier: drei
            // Buttons, einer mit dem langen Text "Weiter aufzeichnen")
            // die intrinsische Breite jedes Kindes berechnet, um zu
            // entscheiden, ob es umbrechen muss. AutoHyphenatingText
            // nutzt dafür intern einen LayoutBuilder, der laut
            // Flutter-Dokumentation KEINE intrinsischen Berechnungen
            // unterstützt ("LayoutBuilder does not support returning
            // intrinsic dimensions") - dieselbe bereits bekannte
            // Einschränkung wie beim SegmentedButton (siehe README
            // Abschnitt 13), hier aber durch OverflowBar statt
            // SegmentedButton ausgelöst. Bei so kurzen Beschriftungen ist
            // Silbentrennung ohnehin nie nötig.
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.cancel),
              child: const Text('Weiter aufzeichnen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.discard),
              child: const Text('Verwerfen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.save),
              child: const Text('Speichern'),
            ),
          ],
        ),
      );

      if (action == null || action == _StopDialogAction.cancel) return;

      if (action == _StopDialogAction.discard) {
        await widget.recordingService.discard();
        return;
      }

      final name = controller.text.trim().isEmpty ? suggested : controller.text.trim();
      final track = await widget.recordingService.stop(name: name);
      if (track != null) {
        await _storageService.save(track);
        await _loadSavedTracks();
      }
    } finally {
      // Unabhaengig davon, welcher Weg oben genommen wurde (return bei
      // "cancel"/"discard" oder normaler Durchlauf) - der Controller wird
      // in jedem Fall sauber freigegeben.
      controller.dispose();
    }
  }

  /// Löscht einen gespeicherten Track (mit Bestätigungsdialog) - wird aus
  /// der noch GEÖFFNETEN Bottom Sheet heraus aufgerufen (siehe
  /// [_showSavedTracksSheet]). [setModalState] ist deren lokaler
  /// Rebuild-Callback: Ohne den zusätzlichen Aufruf hier würde der
  /// gelöschte Track in der bereits sichtbaren Liste fälschlich stehen
  /// bleiben, bis das Sheet geschlossen und erneut geöffnet wird - siehe
  /// Erklärung in [_showSavedTracksSheet]. [sheetContext] (der
  /// `BuildContext` der Sheet-eigenen `StatefulBuilder`-Ebene) dient
  /// ausschließlich der `mounted`-Prüfung direkt davor - falls das Sheet
  /// während der asynchronen Lösch-Operation zwischenzeitlich geschlossen
  /// wurde, würde `setModalState` sonst einen Fehler werfen.
  Future<void> _handleDelete(
    RecordedTrack track,
    BuildContext sheetContext,
    StateSetter setModalState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // title/content bewusst als normale Text-Widgets statt
        // AutoHyphenatingText - siehe ausführliche Begründung beim
        // "Beenden"-Dialog weiter oben (_handleStop): Flutters interne
        // Dialog-Layout-Mechanik führt an mehreren Stellen intrinsische
        // Breitenberechnungen durch, mit denen AutoHyphenatingTexts
        // LayoutBuilder-Ansatz kollidiert.
        title: const Text('Track löschen?'),
        content: Text(
          '"${track.name}" wird endgültig gelöscht.',
        ),
        actions: [
          // Bewusst normale Text-Widgets statt AutoHyphenatingText - siehe
          // ausführliche Begründung beim "Beenden"-Dialog weiter oben
          // (OverflowBar/intrinsische Breitenberechnung in AlertDialog.actions).
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _storageService.delete(track.id);
    await _loadSavedTracks();
    // Aktualisiert die BEREITS GEÖFFNETE Bottom Sheet sofort, damit der
    // gelöschte Track dort unmittelbar verschwindet (siehe
    // _showSavedTracksSheet) - das normale setState in _loadSavedTracks
    // allein reicht dafür nicht aus.
    if (sheetContext.mounted) setModalState(() {});
  }

  /// Exportiert einen gespeicherten Track als GPX-Datei über den nativen
  /// "Teilen"-Dialog (siehe README Abschnitt 20).
  Future<void> _handleExport(RecordedTrack track) async {
    await _importExportService.exportTrack(track);
  }

  /// Öffnet den Datei-Auswahl-Dialog, importiert die gewählte GPX-Datei
  /// und speichert das Ergebnis direkt (analog zum Speichern nach einer
  /// eigenen Aufzeichnung) - siehe README Abschnitt 20. Zeigt bei
  /// ungültigen/unlesbaren Dateien eine verständliche Fehlermeldung statt
  /// die Exception unbehandelt durchzureichen.
  Future<void> _handleImport() async {
    Navigator.of(context).pop(); // Bottom Sheet schliessen
    try {
      final track = await _importExportService.pickAndImportTrack();
      if (track == null) return; // Nutzer hat den Dialog abgebrochen
      await _storageService.save(track);
      await _loadSavedTracks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Track "${track.name}" importiert.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPX-Datei konnte nicht gelesen werden: ${error.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Die Datei konnte nicht importiert werden.')),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recordingSubscription?.cancel();
    _mapEventSubscription?.cancel();
    _uiTicker?.cancel();
    // Bildschirm darf wieder automatisch sperren, sobald die Track-Seite
    // verlassen wird - eine WEITERLAUFENDE Aufzeichnung selbst ist davon
    // nicht betroffen, die lebt unabhaengig im TrackRecordingService
    // weiter (siehe Klassenkommentar).
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.preferences,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // NEU (README Abschnitt 22): Hält TrackRecordingService bei jedem
    // Rebuild (u. a. ausgelöst durch ListenableBuilder auf preferences,
    // siehe build()) mit der aktuell in den Einstellungen gewählten
    // Erinnerungs-Wartezeit synchron - eine reine Feldzuweisung ohne
    // I/O, daher unproblematisch, das bei jedem Rebuild erneut zu tun.
    widget.recordingService.updateReminderMinutes(widget.preferences.autoPauseReminderMinutes);

    switch (_availability) {
      case TrackLocationAvailability.checking:
        return const Center(child: CircularProgressIndicator());
      case TrackLocationAvailability.serviceDisabled:
        return _buildHint(
          icon: Icons.location_off,
          text: 'Der Standortdienst des Geräts ist deaktiviert.',
          buttonLabel: 'Erneut versuchen',
          onPressed: _initialize,
        );
      case TrackLocationAvailability.permissionDenied:
        return _buildHint(
          icon: Icons.location_disabled,
          text: 'Für die Track-Aufzeichnung wird die Standort-Berechtigung benötigt.',
          buttonLabel: 'Erneut versuchen',
          onPressed: _initialize,
        );
      case TrackLocationAvailability.permissionDeniedForever:
        return _buildHint(
          icon: Icons.settings,
          text: 'Die Standort-Berechtigung wurde dauerhaft abgelehnt. '
              'Bitte in den App-Einstellungen des Geräts erteilen.',
          buttonLabel: 'Erneut versuchen',
          onPressed: _initialize,
        );
      case TrackLocationAvailability.ready:
        return _buildReady(context);
    }
  }

  Widget _buildHint({
    required IconData icon,
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            AutoHyphenatingText(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: AutoHyphenatingText(buttonLabel)),
          ],
        ),
      ),
    );
  }

  Widget _buildReady(BuildContext context) {
    final state = widget.recordingService.state;

    return Column(
      children: [
        // NEU (siehe README Abschnitt 37): Oberhalb der Unterreiter
        // platziert, damit sie auf "Karte" UND "Details" gleichermaßen
        // sichtbar ist. Zeigt die auf dieser Seite AKTUELL verwendete
        // Genauigkeitsstufe - hier fest die von TrackRecordingService
        // verwendete (siehe Abschnitt 19), NICHT die auf der
        // Einstellungsseite wählbare (die gilt nur für die Tacho-Seite) -
        // sowie einen kurzen optischen Impuls bei jedem neuen
        // Track-Punkt.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AccuracyBadge(
                mode: SpeedAccuracyMode.fromLocationAccuracy(TrackRecordingService.fixedAccuracy),
              ),
              MeasurementPulseIndicator(pulseKey: _measurementTick),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          // Bewusst normale Text-Labels statt AutoHyphenatingText - siehe
          // dieselbe, bereits mehrfach im Projekt dokumentierte
          // Begründung bei den Unterreitern der Einstellungsseite (README
          // Abschnitt 24/26).
          tabs: const [
            Tab(text: 'Karte'),
            Tab(text: 'Details'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMapTab(context, state),
              _buildDetailsTab(context),
            ],
          ),
        ),
        // NEU (README Abschnitt 29): Start-/Pause-/Beenden-Steuerung
        // sitzt jetzt AUSSERHALB der Unterreiter, unterhalb von beiden
        // gleichermaßen sichtbar - der Nutzer soll die Aufzeichnung auch
        // pausieren/beenden können, während er gerade den Details-Tab
        // betrachtet, nicht nur auf der Karte.
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildControls(context, state),
        ),
      ],
    );
  }

  /// Unterreiter "Karte" - entspricht dem bisherigen, alleinigen
  /// Seiteninhalt (Live-Karte samt Streckenverlauf, Bedien-Icons und
  /// Statuskarte).
  Widget _buildMapTab(BuildContext context, RecordingState state) {
    final nauticalMode = widget.preferences.mapNauticalMode;
    final mapStyle = widget.preferences.mapStyle;
    // Unterer Rand für Statuskarte und Legenden-Button: Bei dauerhaft
    // sichtbarer Quellenangabe (siehe MapStyle) bleibt er frei, mit
    // Zusatz-Overlays wird die Quellenzeile länger (ggf. zwei Zeilen).
    final extraAttribution = nauticalMode || widget.preferences.routeOverlay.isActive;
    final bottomInset = !mapStyle.alwaysVisibleAttribution ? 12.0 : (extraAttribution ? 56.0 : 36.0);
    // Der Legenden-Button sitzt links unten und rückt bei laufender oder
    // pausierter Aufzeichnung über die Statuskarte (ca. 90-110 dp hoch).
    final legendBottom = state != RecordingState.idle ? bottomInset + 108 : bottomInset;
    final liveLatLngs = widget.recordingService.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    final mapCenter = liveLatLngs.isNotEmpty ? liveLatLngs.last : _initialCenter;

    return Stack(
      children: [
        if (mapCenter == null)
          const Center(child: CircularProgressIndicator())
        else
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 16,
              onMapReady: () => _mapReady = true,
              // NEU (README Abschnitt 50): Langes Drücken markiert den Punkt
              // als Ziel.
              onLongPress: (tapPosition, point) => unawaited(_setDestinationFromMapPress(point)),
              // Dreh-Geste wird bei eingerasteter Nordausrichtung
              // gezielt deaktiviert (siehe NorthLockButton), alle
              // anderen Gesten (Verschieben, Zoomen) bleiben
              // uneingeschraenkt nutzbar.
              interactionOptions: InteractionOptions(
                flags: _northLocked ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.all,
              ),
            ),
            children: [
              ...buildMapTileLayers(
                nauticalMode: nauticalMode,
                mapStyle: mapStyle,
                routeOverlay: widget.preferences.routeOverlay,
              ),
              if (liveLatLngs.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: liveLatLngs,
                      strokeWidth: 5,
                      color: const Color(0xFFE53935),
                    ),
                  ],
                ),
              ..._buildDestinationLayers(context),
              MarkerLayer(
                markers: [
                  if (liveLatLngs.isNotEmpty)
                    Marker(
                      point: liveLatLngs.last,
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.my_location,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                    )
                  else if (_initialCenter != null)
                    Marker(
                      point: _initialCenter!,
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.my_location,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                    ),
                ],
              ),
            ],
          ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildSavedTracksButton(context),
        ),
        // NEU (README Abschnitt 50): Ortssuche links oben, daneben (nur bei
        // gesetztem Ziel) die Zielkarte mit Entfernung/Richtung.
        Positioned(
          top: 12,
          left: 12,
          child: _buildSearchButton(context),
        ),
        if (widget.preferences.destination != null)
          Positioned(
            top: 12,
            left: 68,
            right: 68,
            child: _buildDestinationCard(context, widget.preferences.destination!),
          ),
        Positioned(
          top: 68,
          right: 12,
          child: MapStyleButton(preferences: widget.preferences),
        ),
        Positioned(
          left: 12,
          bottom: legendBottom,
          child: MapLegendButton(preferences: widget.preferences),
        ),
        Positioned(
          top: 124,
          right: 12,
          child: NorthLockButton(
            rotationDegrees: _rotationDegrees,
            locked: _northLocked,
            onToggle: () {
              setState(() {
                _northLocked = !_northLocked;
                if (_northLocked) _mapController.rotate(0);
              });
            },
          ),
        ),
        if (state != RecordingState.idle)
          Positioned(
            // Bei dauerhaft sichtbarer Quellenangabe (siehe MapStyle) bleibt
            // der untere Kartenrand frei, damit die Statuskarte sie nicht
            // verdeckt.
            bottom: bottomInset,
            left: 12,
            right: 12,
            child: _buildStatsCard(context, state),
          ),
      ],
    );
  }

  /// NEU (siehe README Abschnitt 29): Unterreiter "Details" - Momentanwerte
  /// (Geschwindigkeit, Kurs, Höhenänderung seit Start, Steigung/Gefälle)
  /// sowie darunter die vier Profil-Diagramme der bisher aufgezeichneten
  /// Strecke. Scrollbar (`SingleChildScrollView`), da Momentanwerte-Karte
  /// plus vier Diagramme auf den meisten Bildschirmen nicht komplett ohne
  /// Scrollen Platz finden.
  Widget _buildDetailsTab(BuildContext context) {
    final points = widget.recordingService.points;
    if (points.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AutoHyphenatingText(
            'Sobald die Aufzeichnung läuft, erscheinen hier Momentanwerte '
            'und Profil-Diagramme.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Einmal pro Rebuild berechnet und sowohl für die Momentanwerte-Karte
    // (letzter Eintrag) als auch für TrackProfileCharts weiterverwendet -
    // siehe Klassenkommentar dort.
    final profile = TrackProfileCalculator.compute(points);
    final latest = profile.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMomentaryValuesCard(context, latest),
          const SizedBox(height: 28),
          TrackProfileCharts(profile: profile),
        ],
      ),
    );
  }

  /// Karte mit den vier geforderten Momentanwerten. `Wrap` statt `Row`,
  /// damit die vier Werte auf schmalen Bildschirmen bzw. bei großer
  /// Systemschrift automatisch in eine zweite Zeile umbrechen, statt
  /// gequetscht zu werden oder überzulaufen.
  /// FEHLERKORREKTUR (siehe README): Statt eines `Wrap` mit fest
  /// verdrahteter Breite je Wert (150 px - nutzte die verfügbare
  /// Kartenbreite nicht aus UND ließ die Werte kleiner wirken als nötig)
  /// jetzt ein 2x2-Raster aus zwei `Row`s mit je zwei `Expanded`-Zellen,
  /// die sich die volle verfügbare Breite gleichmäßig teilen - plus
  /// deutlich größere Schrift für die Werte selbst (siehe
  /// [_buildMomentaryStat]).
  Widget _buildMomentaryValuesCard(BuildContext context, TrackProfilePoint latest) {
    final headingDegrees = widget.recordingService.currentHeadingDegrees;
    final speedKmh = latest.speedMetersPerSecond != null ? latest.speedMetersPerSecond! * 3.6 : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildMomentaryStat(
                    context,
                    'Geschwindigkeit',
                    speedKmh != null ? '${speedKmh.toStringAsFixed(1)} km/h' : '-',
                  ),
                ),
                Expanded(
                  child: _buildMomentaryStat(
                    context,
                    'Kurs über Grund',
                    headingDegrees != null ? '${headingDegrees.round()}°' : '-',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildMomentaryStat(
                    context,
                    'Höhenänderung seit Start',
                    latest.netAltitudeChangeMeters != null
                        ? '${latest.netAltitudeChangeMeters! >= 0 ? '+' : ''}'
                            '${latest.netAltitudeChangeMeters!.toStringAsFixed(0)} m'
                        : '-',
                  ),
                ),
                Expanded(
                  child: _buildMomentaryStat(
                    context,
                    'Steigung / Gefälle',
                    latest.gradientPercent != null
                        ? '${latest.gradientPercent! >= 0 ? '+' : ''}'
                            '${latest.gradientPercent!.toStringAsFixed(1)} %'
                        : '-',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// FEHLERKORREKTUR: Wertgröße von `titleMedium` auf `headlineSmall`
  /// angehoben (deutlich besser ablesbar, z. B. während der Fahrt) -
  /// analog zur bereits bestehenden Vergrößerung der Info-Zeilen auf der
  /// Tacho-Seite (siehe README Abschnitt 11, `_readableInfoStyle`).
  Widget _buildMomentaryStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        AutoHyphenatingText(value, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }

  Widget _buildStatsCard(BuildContext context, RecordingState state) {
    final distanceMeters = widget.recordingService.distanceMeters;
    final duration = widget.recordingService.elapsed;
    // true, solange die aktuelle Pause automatisch durch erkannten
    // Stillstand ausgelöst wurde (statt durch den "Pause"-Button) - siehe
    // TrackRecordingService.
    final autoPaused = widget.recordingService.isAutoPaused;

    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat(context, 'Dauer', TrackFormatter.formatDuration(duration)),
                _buildStat(context, 'Distanz', TrackFormatter.formatDistance(distanceMeters)),
                _buildStat(
                  context,
                  'Ø-Tempo',
                  TrackFormatter.formatAverageSpeed(distanceMeters, duration),
                ),
                if (state == RecordingState.paused)
                  Icon(
                    autoPaused ? Icons.pause_circle_outline : Icons.pause_circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            // Nur bei automatischer (nicht bei manueller) Pause sichtbar -
            // erklärt dem Nutzer, warum die Aufzeichnung gerade pausiert,
            // ohne dass er selbst "Pause" angetippt hat.
            if (autoPaused) ...[
              const SizedBox(height: 8),
              AutoHyphenatingText(
                'Stillstand erkannt - Aufzeichnung automatisch pausiert',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AutoHyphenatingText(label, style: Theme.of(context).textTheme.labelSmall),
        AutoHyphenatingText(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  // ==== NEU (README Abschnitt 50): Ortssuche und Ziel ====

  /// Zuletzt bekannte eigene Position (aktuellster Aufzeichnungspunkt,
  /// sonst die einmalig ermittelte Startposition) - Bezugspunkt für
  /// Entfernung und Richtung zum Ziel.
  LatLng? _referencePoint() {
    final points = widget.recordingService.points;
    if (points.isNotEmpty) {
      return LatLng(points.last.latitude, points.last.longitude);
    }
    return _initialCenter;
  }

  Future<void> _openPlaceSearch() async {
    final place = await showModalBottomSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(service: _placeSearchService),
    );
    if (place == null || !mounted) return;
    await _setDestination(place);
  }

  /// Setzt das Ziel; [showOnMap] zeigt es zusätzlich auf der Karte
  /// (eigene Position und Ziel im Bild) - beim langen Drücken auf die
  /// Karte bewusst aus, dort würde ein Kamerasprung stören.
  Future<void> _setDestination(PlaceResult place, {bool showOnMap = true}) async {
    await widget.preferences.setDestination(place);
    if (!mounted || !showOnMap) return;
    _showDestinationOnMap(place);
  }

  Future<void> _setDestinationFromMapPress(LatLng point) {
    return _setDestination(
      PlaceResult(
        name: 'Markierter Punkt',
        displayName: 'Markierter Punkt',
        latitude: point.latitude,
        longitude: point.longitude,
      ),
      showOnMap: false,
    );
  }

  void _showDestinationOnMap(PlaceResult place) {
    if (!_mapReady) return;
    // Automatisches Mitführen kurz aussetzen, siehe _followPausedUntil.
    _followPausedUntil = DateTime.now().add(const Duration(seconds: 20));

    final destination = LatLng(place.latitude, place.longitude);
    final reference = _referencePoint();
    final distance = reference == null
        ? 0.0
        : Geolocator.distanceBetween(
            reference.latitude,
            reference.longitude,
            destination.latitude,
            destination.longitude,
          );
    // Ohne eigene Position bzw. bei (fast) gleichem Ort: nur zum Ziel
    // springen - ein Rahmen um zwei fast identische Punkte ergäbe eine
    // unbrauchbare Zoomstufe.
    if (reference == null || distance < 50) {
      _mapController.move(destination, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(reference, destination),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 120),
      ),
    );
  }

  /// Marker für das Ziel - Spitze der Nadel liegt auf dem Zielpunkt
  /// (`alignment: Alignment.topCenter` platziert das Symbol ÜBER dem Punkt).
  List<Widget> _buildDestinationLayers(BuildContext context) {
    final destination = widget.preferences.destination;
    if (destination == null) return const [];
    return [
      MarkerLayer(
        markers: [
          Marker(
            point: LatLng(destination.latitude, destination.longitude),
            width: 40,
            height: 40,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.place, color: Color(0xFFE53935), size: 40),
          ),
        ],
      ),
    ];
  }

  Widget _buildSearchButton(BuildContext context) {
    return Tooltip(
      message: 'Ort suchen',
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openPlaceSearch,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    );
  }

  /// Karte mit Zielname sowie Luftlinie und Richtung von der eigenen
  /// Position (sofern bekannt). Antippen zeigt das Ziel auf der Karte, das
  /// Kreuz entfernt es. Bewusst normale Text-Widgets (Ellipsis in
  /// beengtem Layout, siehe README Abschnitt 13/24/26).
  Widget _buildDestinationCard(BuildContext context, PlaceResult destination) {
    final theme = Theme.of(context);
    final reference = _referencePoint();
    String? info;
    if (reference != null) {
      final meters = Geolocator.distanceBetween(
        reference.latitude,
        reference.longitude,
        destination.latitude,
        destination.longitude,
      );
      final bearing = Geolocator.bearingBetween(
        reference.latitude,
        reference.longitude,
        destination.latitude,
        destination.longitude,
      );
      info = 'Luftlinie ${TrackFormatter.formatDistance(meters)} · '
          '${bearing.round() % 360}\u00B0';
    }

    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDestinationOnMap(destination),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              const Icon(Icons.place, color: Color(0xFFE53935)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      destination.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (info != null)
                      Text(
                        info,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ziel entfernen',
                icon: const Icon(Icons.close),
                onPressed: () => widget.preferences.setDestination(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedTracksButton(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showSavedTracksSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.list_alt, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _handleStart,
            icon: const Icon(Icons.fiber_manual_record),
            label: AutoHyphenatingText('Aufzeichnung starten'),
          ),
        );
      case RecordingState.recording:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _handlePause,
                icon: const Icon(Icons.pause),
                label: AutoHyphenatingText('Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _handleStop,
                icon: const Icon(Icons.stop),
                label: AutoHyphenatingText('Beenden'),
              ),
            ),
          ],
        );
      case RecordingState.paused:
        // WICHTIG: "Pause" und "Fortsetzen" sind funktional unabhängige
        // Aktionen (siehe TrackRecordingService.pause/resume) - deshalb
        // wird der "Pause"-Button bei einer AUTOMATISCHEN Pause
        // zusätzlich (nicht ersetzend) zu "Fortsetzen" angezeigt: Ein Tap
        // darauf "fixiert" die laufende Pause als manuell (verhindert,
        // dass sie bei der nächsten kurzen Bewegung - z. B. beim
        // Griff zum Handy - ungewollt automatisch wieder aufgehoben
        // wird), OHNE die Aufzeichnung fortzusetzen. Bei einer bereits
        // manuellen Pause wäre ein zusätzlicher "Pause"-Tap dagegen
        // wirkungslos (siehe TrackRecordingService.pause) und wird
        // deshalb hier gar nicht erst angeboten.
        final autoPaused = widget.recordingService.isAutoPaused;
        return Row(
          children: [
            if (autoPaused) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handlePause,
                  icon: const Icon(Icons.pause),
                  label: AutoHyphenatingText('Pause'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _handleResume,
                icon: const Icon(Icons.play_arrow),
                label: AutoHyphenatingText('Fortsetzen'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _handleStop,
                icon: const Icon(Icons.stop),
                label: AutoHyphenatingText('Beenden'),
              ),
            ),
          ],
        );
    }
  }

  /// Öffnet die Liste gespeicherter Tracks als Bottom Sheet.
  ///
  /// WICHTIG: `showModalBottomSheet` fügt seinen Inhalt als EIGENE Route
  /// in den Navigator ein - das ist NICHT Teil des von `build()`
  /// zurückgegebenen Widget-Baums dieser Seite. Ein `setState()` auf
  /// `_TrackPageState` (z. B. in [_loadSavedTracks]) aktualisiert daher
  /// zwar `_savedTracks`, löst aber KEINEN Rebuild des bereits
  /// GEÖFFNETEN Sheets aus - das würde die Liste erst beim nächsten
  /// Öffnen/Schließen aktualisieren. Der `StatefulBuilder` hier stellt
  /// mit `setModalState` einen eigenen, lokal für dieses Sheet gültigen
  /// Rebuild-Mechanismus bereit, den [_handleDelete] nach dem Löschen
  /// zusätzlich zum normalen `setState` aufruft (siehe dort).
  void _showSavedTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AutoHyphenatingText(
                              'Gespeicherte Tracks',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Track importieren (GPX)',
                            icon: const Icon(Icons.file_download_outlined),
                            onPressed: _handleImport,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _buildSavedTracksList(
                          context,
                          scrollController,
                          setModalState,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSavedTracksList(
    BuildContext context,
    ScrollController scrollController,
    StateSetter setModalState,
  ) {
    if (_loadingSavedTracks) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_savedTracks.isEmpty) {
      return Center(
        child: AutoHyphenatingText(
          'Noch keine Tracks gespeichert.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: _savedTracks.length,
      itemBuilder: (context, index) {
        final track = _savedTracks[index];
        return ListTile(
          leading: const Icon(Icons.route),
          title: AutoHyphenatingText(track.name),
          subtitle: AutoHyphenatingText(
            '${TrackFormatter.formatDateTime(track.startTime)} · '
            '${TrackFormatter.formatDistance(track.distanceMeters)} · '
            '${TrackFormatter.formatDuration(track.recordedDuration)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Als GPX exportieren',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _handleExport(track),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _handleDelete(track, context, setModalState),
              ),
            ],
          ),
          onTap: () => _openTrackDetail(track),
        );
      },
    );
  }
}
