import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/recorded_track.dart';
import '../services/app_preferences.dart';
import '../services/track_import_export_service.dart';
import '../services/track_recording_service.dart';
import '../services/track_storage_service.dart';
import '../util/track_formatter.dart';
import 'track_detail_page.dart';
import 'widgets/map_tile_layers.dart';
import 'widgets/nautical_mode_button.dart';
import 'widgets/north_lock_button.dart';

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

class _TrackPageState extends State<TrackPage> {
  final TrackStorageService _storageService = TrackStorageService();
  final TrackImportExportService _importExportService = TrackImportExportService();
  final MapController _mapController = MapController();

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
  bool _northLocked = false;

  @override
  void initState() {
    super.initState();
    _recordingSubscription = widget.recordingService.updates.listen((_) {
      if (!mounted) return;
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
    widget.recordingService.start();
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
    final nauticalMode = widget.preferences.mapNauticalMode;
    final liveLatLngs = widget.recordingService.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    final mapCenter = liveLatLngs.isNotEmpty ? liveLatLngs.last : _initialCenter;

    return Column(
      children: [
        Expanded(
          child: Stack(
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
                    // Dreh-Geste wird bei eingerasteter Nordausrichtung
                    // gezielt deaktiviert (siehe NorthLockButton), alle
                    // anderen Gesten (Verschieben, Zoomen) bleiben
                    // uneingeschraenkt nutzbar.
                    interactionOptions: InteractionOptions(
                      flags: _northLocked
                          ? InteractiveFlag.all & ~InteractiveFlag.rotate
                          : InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    ...buildMapTileLayers(nauticalMode: nauticalMode),
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
              Positioned(
                top: 68,
                right: 12,
                child: NauticalModeButton(
                  nauticalMode: nauticalMode,
                  onChanged: widget.preferences.setMapNauticalMode,
                ),
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
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: _buildStatsCard(context, state),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildControls(context, state),
        ),
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
