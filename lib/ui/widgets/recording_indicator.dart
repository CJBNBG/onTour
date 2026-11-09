import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/track_recording_service.dart';

/// Optische Rückmeldung über eine Track-Aufzeichnung (siehe README
/// Abschnitte 64/65):
/// - sanft blinkender ROTER PUNKT: es wird tatsächlich aufgezeichnet;
/// - PAUSE-Symbol: Aufzeichnung pausiert (manuell oder automatisch bei
///   Stillstand);
/// - blinkendes WARN-DREIECK "Unterbrochen": der Aufzeichnungszustand
///   besteht, aber der Dienst liefert nicht mehr (Positions-Stream
///   ausgefallen oder länger keine Position, siehe
///   [TrackRecordingService.interruptionReason]) - der rote Punkt erscheint
///   dann ausdrücklich NICHT. Antippen/Tooltip nennen den Grund.
/// - nichts: keine Aufzeichnung (das Widget belegt dann keinen Platz).
///
/// Hört auf [TrackRecordingService.updates] und prüft zusätzlich alle 2 s
/// selbst, denn eine Unterbrechung entsteht durch Ausbleiben von Daten -
/// also ohne dass ein Ereignis eintrifft. Baut sich nur bei einer
/// Änderung des angezeigten Zustands neu auf.
class RecordingIndicator extends StatefulWidget {
  final TrackRecordingService service;

  /// Antippen, z. B. um zur Track-Seite zu wechseln.
  final VoidCallback? onTap;

  const RecordingIndicator({super.key, required this.service, this.onTap});

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator>
    with SingleTickerProviderStateMixin {
  static const Duration _recordingBlink = Duration(milliseconds: 1100);
  static const Duration _warningBlink = Duration(milliseconds: 600);

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: _recordingBlink,
  );
  late final Animation<double> _opacity = Tween<double>(begin: 0.3, end: 1).animate(_blink);

  StreamSubscription<void>? _subscription;
  Timer? _timer;

  late RecordingState _state = widget.service.state;
  late String? _reason = widget.service.interruptionReason;

  @override
  void initState() {
    super.initState();
    _syncBlink();
    _subscription = widget.service.updates.listen((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    final state = widget.service.state;
    final reason = widget.service.interruptionReason;
    if (state == _state && reason == _reason) return;
    setState(() {
      _state = state;
      _reason = reason;
    });
    _syncBlink();
  }

  /// Blinken bei aktiver Aufzeichnung (langsam) und bei Warnung (schnell) -
  /// sonst steht die Animation still und verbraucht nichts.
  void _syncBlink() {
    if (_state == RecordingState.idle || (_state == RecordingState.paused && _reason == null)) {
      _blink.stop();
      return;
    }
    final period = _reason != null ? _warningBlink : _recordingBlink;
    _blink.repeat(reverse: true, period: period);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == RecordingState.idle) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final reason = _reason;
    final recording = _state == RecordingState.recording;

    final Widget icon;
    final String label;
    final String tooltip;
    Color? labelColor;
    if (reason != null) {
      icon = FadeTransition(
        opacity: _opacity,
        child: Icon(Icons.warning_amber_rounded, size: 30, color: theme.colorScheme.error),
      );
      label = 'Unterbrochen';
      labelColor = theme.colorScheme.error;
      tooltip = 'Aufzeichnung unterbrochen: $reason';
    } else if (recording) {
      icon = FadeTransition(
        opacity: _opacity,
        child: const Icon(Icons.fiber_manual_record, size: 30, color: Colors.red),
      );
      label = 'Aufnahme';
      tooltip = 'Aufzeichnung läuft';
    } else {
      icon = const Icon(Icons.pause_circle, size: 30, color: Colors.orange);
      label = 'Pausiert';
      tooltip = 'Aufzeichnung pausiert';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                // Bewusst normales Text-Widget (kurzer Einzeiler in
                // beengtem Layout, siehe README Abschnitt 13).
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: reason != null ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
