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
          title: AutoHyphenatingText('Aufzeichnung beenden'),
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
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.cancel),
              child: AutoHyphenatingText('Weiter aufzeichnen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.discard),
              child: AutoHyphenatingText('Verwerfen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_StopDialogAction.save),
              child: AutoHyphenatingText('Speichern'),
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

  Future<void> _handleDelete(RecordedTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AutoHyphenatingText('Track löschen?'),
        content: AutoHyphenatingText(
          '"${track.name}" wird endgültig gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: AutoHyphenatingText('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: AutoHyphenatingText('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _storageService.delete(track.id);
    await _loadSavedTracks();
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

    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
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
              Icon(Icons.pause_circle, color: Theme.of(context).colorScheme.primary),
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
        return Row(
          children: [
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

  void _showSavedTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
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
                        icon: const Icon(Icons.file_upload_outlined),
                        onPressed: _handleImport,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _buildSavedTracksList(context, scrollController)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSavedTracksList(BuildContext context, ScrollController scrollController) {
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
                onPressed: () => _handleDelete(track),
              ),
            ],
          ),
          onTap: () => _openTrackDetail(track),
        );
      },
    );
  }
}
