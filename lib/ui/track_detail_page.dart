import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/recorded_track.dart';
import '../services/app_preferences.dart';
import '../services/track_import_export_service.dart';
import '../services/track_storage_service.dart';
import '../util/track_formatter.dart';
import '../util/track_profile_calculator.dart';
import 'widgets/map_tile_layers.dart';
import 'widgets/map_legend_button.dart';
import 'widgets/map_style_button.dart';
import 'widgets/north_lock_button.dart';
import 'widgets/track_profile_charts.dart';

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
///
/// NEU (siehe README Abschnitt 29): Zwei Unterreiter "Karte" und
/// "Details" (analog zu TrackPage) - "Details" zeigt die vier Profil-
/// Diagramme (Geschwindigkeit, Höhe, Anstieg, Steigung/Gefälle) des
/// gesamten gespeicherten Tracks. Anders als auf der laufenden
/// Aufzeichnung gibt es hier bewusst KEINE Momentanwerte-Karte - ein
/// bereits abgeschlossener Track hat kein sinnvolles "jetzt" mehr. Die
/// Unterreiter sitzen hier (anders als bei TrackPage, das sich die
/// AppBar mit den übrigen Hauptseiten teilt, siehe HomeShell) direkt in
/// der eigenen `AppBar` dieser Seite (`bottom: TabBar(...)`), da
/// TrackDetailPage eine eigenständige, per `Navigator.push` geöffnete
/// Seite mit eigener AppBar ist.
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

class _TrackDetailPageState extends State<TrackDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  final MapController _mapController = MapController();
  final TrackStorageService _storageService = TrackStorageService();
  final TrackImportExportService _importExportService = TrackImportExportService();
  bool _mapReady = false;


  late final List<LatLng> _points = widget.track.points
      .map((p) => LatLng(p.latitude, p.longitude))
      .toList();

  /// NEU (siehe README Abschnitt 29): Einmalig berechnet (der Track ist
  /// bereits abgeschlossen, seine Punkte ändern sich nicht mehr) - liefert
  /// die Datengrundlage für TrackProfileCharts auf dem Details-Tab.
  late final List<TrackProfilePoint> _profile = TrackProfileCalculator.compute(widget.track.points);

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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        // title/content bewusst als normale Text-Widgets statt
        // AutoHyphenatingText - siehe ausführliche Begründung in
        // track_page.dart (_handleStop): Flutters interne
        // Dialog-Layout-Mechanik führt an mehreren Stellen intrinsische
        // Breitenberechnungen durch (nicht nur bei den actions über
        // OverflowBar, auch title/content selbst sind betroffen), mit
        // denen AutoHyphenatingTexts LayoutBuilder-Ansatz kollidiert.
        title: const Text('Track löschen?'),
        content: Text(
          '"${widget.track.name}" wird endgültig gelöscht.',
        ),
        actions: [
          // Bewusst normale Text-Widgets statt AutoHyphenatingText - siehe
          // ausführliche Begründung in track_page.dart (_handleStop):
          // AlertDialog.actions wird über ein OverflowBar layoutet, das
          // intrinsische Breitenberechnungen benötigt, die
          // AutoHyphenatingText (LayoutBuilder-basiert) nicht unterstützt.
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
        // NEU (siehe README Abschnitt 29): Unterreiter "Karte"/"Details" -
        // nur sinnvoll anzeigbar, wenn überhaupt Positionsdaten vorliegen
        // (siehe _buildBody, das sonst direkt eine Hinweismeldung ohne
        // Tabs zeigt) - PreferredSize mit Höhe 0 blendet die TabBar in
        // diesem Fall einfach unsichtbar aus, statt eine leere/nutzlose
        // TabBar anzuzeigen.
        bottom: _points.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Karte'),
                  Tab(text: 'Details'),
                ],
              ),
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
    if (_points.isEmpty) {
      return Center(
        child: AutoHyphenatingText(
          'Dieser Track enthält keine Positionsdaten.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildMapTab(context),
        _buildDetailsTab(context),
      ],
    );
  }

  /// Unterreiter "Karte" - entspricht dem bisherigen, alleinigen
  /// Seiteninhalt (Streckenverlauf samt Start-/Endmarker, Bedien-Icons und
  /// Statuskarte).
  Widget _buildMapTab(BuildContext context) {
    final nauticalMode = widget.preferences.mapNauticalMode;
    // Legenden-Button links unten; bei dauerhaft sichtbarer Quellenangabe
    // (siehe MapStyle) oberhalb davon, damit er sie nicht verdeckt.
    final legendBottom = !widget.preferences.mapStyle.alwaysVisibleAttribution
        ? 12.0
        : (nauticalMode || widget.preferences.routeOverlay.isActive ? 56.0 : 36.0);

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
                  ...buildMapTileLayers(
                    nauticalMode: nauticalMode,
                    mapStyle: widget.preferences.mapStyle,
                    routeOverlay: widget.preferences.routeOverlay,
                  ),
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
                child: MapStyleButton(preferences: widget.preferences),
              ),
              Positioned(
                left: 12,
                bottom: legendBottom,
                child: MapLegendButton(preferences: widget.preferences),
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

  /// NEU (siehe README Abschnitt 29): Unterreiter "Details" - ausschließlich
  /// die vier Profil-Diagramme des gesamten Tracks, siehe Klassenkommentar
  /// für die Begründung, warum es hier (anders als bei der laufenden
  /// Aufzeichnung) keine Momentanwerte-Karte gibt.
  Widget _buildDetailsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TrackProfileCharts(profile: _profile),
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
