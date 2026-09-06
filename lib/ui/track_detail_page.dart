import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/recorded_track.dart';
import '../services/app_preferences.dart';
import '../services/track_import_export_service.dart';
import '../services/track_storage_service.dart';
import '../util/track_formatter.dart';
import 'widgets/map_tile_layers.dart';
import 'widgets/nautical_mode_button.dart';
import 'widgets/north_lock_button.dart';

/// Detailansicht eines einzelnen gespeicherten Tracks: Streckenverlauf auf
/// derselben umschaltbaren Karte (Landkarte/Seekarte samt
/// Nordausrichtungs-Fixierung) wie die Track-Aufzeichnung, dazu
/// Kennzahlen (Distanz, Dauer, Ø-Tempo, Datum) sowie die Möglichkeit, den
/// Track von hier aus zu löschen oder als GPX-Datei zu exportieren (siehe
/// README Abschnitt 20).
///
/// Wird per `Navigator.push` von der Liste gespeicherter Tracks in
/// `track_page.dart` aus geöffnet - siehe dortiger Kommentar sowie README
/// Abschnitt 9/19. Ersetzt die frühere, eigenständige Kartenseite
/// (`map_page.dart`), die nur die aktuelle Live-Position ohne weiteren
/// Kontext zeigte; diese Funktion ist in der Track-Aufzeichnung selbst
/// bereits enthalten, wodurch eine separate reine "Wo bin ich"-Seite
/// entfällt.
class TrackDetailPage extends StatefulWidget {
  final RecordedTrack track;
  final AppPreferences preferences;

  const TrackDetailPage({
    super.key,
    required this.track,
    required this.preferences,
  });

  @override
  State<TrackDetailPage> createState() => _TrackDetailPageState();
}

class _TrackDetailPageState extends State<TrackDetailPage> {
  final MapController _mapController = MapController();
  final TrackStorageService _storageService = TrackStorageService();
  final TrackImportExportService _importExportService = TrackImportExportService();
  bool _mapReady = false;


  late final List<LatLng> _points = widget.track.points
      .map((p) => LatLng(p.latitude, p.longitude))
      .toList();

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
    _mapController.mapEventStream.listen((event) {
      if (!mounted) return;
      setState(() => _rotationDegrees = event.camera.rotation);
    });
  }

  LatLngBounds? _bounds() {
    if (_points.isEmpty) return null;
    var minLat = _points.first.latitude, maxLat = _points.first.latitude;
    var minLng = _points.first.longitude, maxLng = _points.first.longitude;
    for (final p in _points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void _fitToBounds() {
    final bounds = _bounds();
    if (bounds == null || !_mapReady) return;
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AutoHyphenatingText('Track löschen?'),
        content: AutoHyphenatingText(
          '"${widget.track.name}" wird endgültig gelöscht.',
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

    await _storageService.delete(widget.track.id);
    if (!mounted) return;
    // true signalisiert der aufrufenden TrackPage, dass die Liste
    // gespeicherter Tracks neu geladen werden sollte.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AutoHyphenatingText(widget.track.name),
        actions: [
          IconButton(
            tooltip: 'Als GPX exportieren',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _importExportService.exportTrack(widget.track),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _handleDelete,
          ),
        ],
      ),
      // ListenableBuilder sorgt dafür, dass ein Umschalten auf die
      // Seekarte (persistiert in AppPreferences, siehe
      // NauticalModeButton) sofort auch hier sichtbar wird - genau wie
      // zuvor in der eigenständigen Kartenseite.
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.preferences,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final nauticalMode = widget.preferences.mapNauticalMode;

    if (_points.isEmpty) {
      return Center(
        child: AutoHyphenatingText(
          'Dieser Track enthält keine Positionsdaten.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _points.first,
                  initialZoom: 15,
                  // Nordausrichtungs-Fixierung: siehe NorthLockButton bzw.
                  // die identische Logik in TrackPage/der frueheren
                  // eigenstaendigen Kartenseite.
                  interactionOptions: InteractionOptions(
                    flags: _northLocked
                        ? InteractiveFlag.all & ~InteractiveFlag.rotate
                        : InteractiveFlag.all,
                  ),
                  onMapReady: () {
                    _mapReady = true;
                    // Nach dem ersten Layout ausfuehren, damit die Karte
                    // bereits eine gueltige Groesse hat.
                    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToBounds());
                  },
                ),
                children: [
                  ...buildMapTileLayers(nauticalMode: nauticalMode),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _points,
                        strokeWidth: 5,
                        color: const Color(0xFFE53935),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _points.first,
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.trip_origin,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      if (_points.length > 1)
                        Marker(
                          point: _points.last,
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.flag,
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
                child: NauticalModeButton(
                  nauticalMode: nauticalMode,
                  onChanged: widget.preferences.setMapNauticalMode,
                ),
              ),
              Positioned(
                top: 68,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildStatsCard(context),
        ),
      ],
    );
  }

  Widget _buildStatsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoHyphenatingText(
              TrackFormatter.formatDateTime(widget.track.startTime),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat(context, 'Distanz', TrackFormatter.formatDistance(widget.track.distanceMeters)),
                _buildStat(context, 'Dauer', TrackFormatter.formatDuration(widget.track.recordedDuration)),
                _buildStat(
                  context,
                  'Ø-Tempo',
                  TrackFormatter.formatAverageSpeed(
                    widget.track.distanceMeters,
                    widget.track.recordedDuration,
                  ),
                ),
              ],
            ),
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
}
