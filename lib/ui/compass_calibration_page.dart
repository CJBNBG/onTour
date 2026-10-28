import 'dart:async';
import 'dart:math' as math;

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/compass_reading.dart';
import '../services/compass_service.dart';

/// Geführte Kompass-Kalibrierung (siehe README Abschnitt 48): Eine
/// animierte liegende Acht zeigt die Bewegung, ein Fortschrittsbalken
/// erfasst, wie vollständig das Gerät dabei gedreht/gekippt wurde, und die
/// Live-Anzeige der Magnetfeldstärke bestätigt, sobald das Feld wieder
/// plausibel ist.
///
/// WICHTIG (ehrlich zur Funktion): Android bietet Apps keine Möglichkeit,
/// die Kalibrierung des Magnetsensors selbst auszulösen - das System
/// kalibriert ihn eigenständig, solange das Gerät ausreichend bewegt wird.
/// Diese Seite führt den Nutzer durch genau diese Bewegung und zeigt das
/// Ergebnis an; sie rechnet selbst nichts am Sensor um. Eine ÄUSSERE
/// Störung (Karosserie, Magnethalterung, Metall) lässt sich damit nicht
/// beheben - dann bleibt das Feld gestört, und die Seite weist darauf hin.
///
/// Feldstärke und Störungsstatus stammen aus dem bereits laufenden
/// [CompassService] (derselbe, entprellte Wert wie der Warn-Chip auf der
/// Kompass-Seite); nur die Bewegungsabdeckung wird hier aus dem rohen
/// Magnetometer-Stream bestimmt.
class CompassCalibrationPage extends StatefulWidget {
  final CompassService compassService;

  const CompassCalibrationPage({super.key, required this.compassService});

  @override
  State<CompassCalibrationPage> createState() => _CompassCalibrationPageState();
}

class _CompassCalibrationPageState extends State<CompassCalibrationPage>
    with SingleTickerProviderStateMixin {
  /// Einteilung der Richtungen des Magnetfeldvektors im GERÄTEKOORDINATEN-
  /// system in Kacheln (Azimut x Elevation) - je mehr verschiedene Kacheln
  /// beim Drehen durchlaufen werden, desto vollständiger wurde das Gerät
  /// bewegt.
  static const int _azimuthBins = 8;
  static const int _elevationBins = 4;

  /// Anteil der Kacheln, der als "ausreichend bewegt" gilt - bewusst
  /// deutlich unter 100 %, da nicht alle Kacheln bei normaler
  /// Handbewegung erreichbar sind.
  static const double _requiredCoverage = 0.4;

  static final NumberFormat _fieldFormat = NumberFormat('0', 'de_DE');

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  StreamSubscription<CompassReading>? _readingSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  CompassReading? _reading;
  final Set<int> _visitedBins = {};
  bool _completed = false;

  double get _coverage => (_visitedBins.length / (_azimuthBins * _elevationBins));

  /// Fortschritt für den Balken: erreichen der Mindestabdeckung = 100 %.
  double get _progress => (_coverage / _requiredCoverage).clamp(0.0, 1.0).toDouble();

  bool get _coverageReached => _coverage >= _requiredCoverage;

  @override
  void initState() {
    super.initState();
    // Zweiter Listener auf den bereits von CompassPage genutzten
    // Broadcast-Stream - startet keine zusätzlichen Sensoren des
    // CompassService.
    _readingSubscription = widget.compassService.readingStream().listen((reading) {
      if (!mounted) return;
      setState(() {
        _reading = reading;
        _updateCompletion();
      });
    });
    // Fehler (kein Magnetometer) bewusst verschluckt - dann bleibt der
    // Fortschritt bei 0, die Seite funktioniert aber weiter.
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onMagnetometer, onError: (Object error) {});
  }

  void _onMagnetometer(MagnetometerEvent e) {
    final norm = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (norm < 1e-3) return;
    final azimuth = math.atan2(e.y, e.x); // -pi .. pi
    final elevation = math.asin((e.z / norm).clamp(-1.0, 1.0)); // -pi/2 .. pi/2
    final a = (((azimuth + math.pi) / (2 * math.pi)) * _azimuthBins)
        .floor()
        .clamp(0, _azimuthBins - 1);
    final b = (((elevation + math.pi / 2) / math.pi) * _elevationBins)
        .floor()
        .clamp(0, _elevationBins - 1);
    if (_visitedBins.add(a * _elevationBins + b)) {
      if (!mounted) return;
      setState(_updateCompletion);
    }
  }

  /// Abgeschlossen, sobald genug Bewegung erfasst wurde UND das Feld
  /// plausibel (nicht gestört) ist. Einmal erreicht, bleibt der Zustand
  /// bis zum Neustart bestehen (kein Flackern).
  void _updateCompletion() {
    final reading = _reading;
    if (_completed || reading == null) return;
    if (_coverageReached && !reading.isDisturbed && reading.fieldStrengthMicroTesla != null) {
      _completed = true;
    }
  }

  void _restart() {
    setState(() {
      _visitedBins.clear();
      _completed = false;
    });
  }

  @override
  void dispose() {
    _readingSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reading = _reading;
    final disturbed = reading?.isDisturbed ?? false;
    final strength = reading?.fieldStrengthMicroTesla;

    return Scaffold(
      appBar: AppBar(title: AutoHyphenatingText('Kompass kalibrieren')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(
              height: 180,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => CustomPaint(
                  painter: _FigureEightPainter(
                    progress: _animation.value,
                    pathColor: scheme.primary.withValues(alpha: 0.35),
                    dotColor: scheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AutoHyphenatingText(
              'Halte das Gerät in der Hand und bewege es in einer großen '
              'liegenden Acht - dabei auch drehen und kippen, sodass alle '
              'Seiten einmal nach oben zeigen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            AutoHyphenatingText(
              'Bewegung erfasst',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _progress, minHeight: 12),
            ),
            const SizedBox(height: 24),
            AutoHyphenatingText(
              strength != null
                  ? 'Magnetfeld: ${_fieldFormat.format(strength)} µT'
                  : 'Magnetfeld: nicht verfügbar',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              'Normal sind ca. 25-65 µT.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _buildStatusCard(context, disturbed: disturbed, hasReading: strength != null),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh),
                    label: AutoHyphenatingText('Neu starten'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check),
                    label: AutoHyphenatingText('Fertig'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AutoHyphenatingText(
              'Hinweis: Android lässt Apps die Kalibrierung des '
              'Magnetsensors nicht selbst starten - das System justiert ihn '
              'selbstständig, während das Gerät bewegt wird. Diese Seite '
              'führt dich durch die Bewegung und zeigt, ob das Magnetfeld '
              'danach wieder normal ist.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Statuskarte: Erfolg, anhaltende Störung (trotz genug Bewegung) oder
  /// Anleitung - jeweils mit passender Farbe/Icon.
  Widget _buildStatusCard(
    BuildContext context, {
    required bool disturbed,
    required bool hasReading,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final IconData icon;
    final Color background;
    final Color foreground;
    final String text;

    if (_completed) {
      icon = Icons.check_circle_outline;
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
      text = 'Fertig - das Magnetfeld ist wieder im Normalbereich. Der '
          'Kompass sollte jetzt zuverlässig anzeigen.';
    } else if (!hasReading) {
      icon = Icons.info_outline;
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      text = 'Warte auf Messwerte des Magnetsensors …';
    } else if (disturbed && _coverageReached) {
      icon = Icons.warning_amber_rounded;
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
      text = 'Das Feld ist trotz der Bewegung weiterhin gestört. Vermutlich '
          'liegt eine äußere Störquelle in der Nähe (Metall, Magnete, '
          'Lautsprecher, Fahrzeugkarosserie, Magnethalterung). Entferne dich '
          'ein paar Meter davon oder nimm das Gerät aus der Halterung und '
          'starte neu.';
    } else if (disturbed) {
      icon = Icons.warning_amber_rounded;
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
      text = 'Das Magnetfeld ist derzeit gestört. Bewege das Gerät weiter - '
          'und halte Abstand zu Metall, Magneten und Lautsprechern.';
    } else if (_coverageReached) {
      icon = Icons.hourglass_bottom;
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      text = 'Genug Bewegung erfasst - einen Moment, das Feld wird noch '
          'geprüft.';
    } else {
      icon = Icons.info_outline;
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      text = 'Das Magnetfeld ist derzeit im Normalbereich. Du kannst die '
          'Kalibrierung trotzdem durchführen, um den Sensor neu zu '
          'justieren.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: AutoHyphenatingText(text, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

/// Zeichnet eine liegende Acht (Lemniskate) als Bahn samt einem darauf
/// wandernden Punkt - Anleitung für die gewünschte Gerätebewegung.
class _FigureEightPainter extends CustomPainter {
  final double progress; // 0..1, ein voller Durchlauf der Acht
  final Color pathColor;
  final Color dotColor;

  _FigureEightPainter({
    required this.progress,
    required this.pathColor,
    required this.dotColor,
  });

  Offset _pointAt(double u, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final a = size.width * 0.38;
    final b = size.height * 0.42;
    return Offset(cx + math.sin(u) * a, cy + math.sin(2 * u) / 2 * b);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final p = _pointAt(i / steps * 2 * math.pi, size);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = pathColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    final dot = _pointAt(progress * 2 * math.pi, size);
    canvas.drawCircle(dot, 12, Paint()..color = dotColor.withValues(alpha: 0.25));
    canvas.drawCircle(dot, 7, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(covariant _FigureEightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pathColor != pathColor ||
      oldDelegate.dotColor != dotColor;
}
