import 'package:flutter/material.dart';

/// Blitzt kurz auf, sobald sich [pulseKey] ändert - als optische
/// Rückmeldung, dass gerade eine neue Messung eingetroffen ist (siehe
/// README Abschnitt 37). Der Aufrufer erhöht dafür einfach einen
/// Zähler bei jeder neuen Messung und übergibt ihn als [pulseKey]; diese
/// Klasse selbst kennt die fachliche Bedeutung einer "Messung" nicht -
/// dadurch auf Tacho-, Kompass- UND Track-Seite gleichermaßen
/// einsetzbar, obwohl dort jeweils ganz unterschiedliche Dinge eine
/// neue Messung auslösen (neuer SpeedReading- bzw. AltitudeReading-Wert,
/// neuer TrackPoint).
///
/// Bewusst als kurzer, schneller "Blitz" (schnelles Einblenden, etwas
/// langsameres Ausblenden) statt eines symmetrischen Auf-und-Ab
/// umgesetzt - wirkt dadurch eher wie ein einzelner Impuls/"Klick" als
/// wie ein durchgehendes Pulsieren.
class MeasurementPulseIndicator extends StatefulWidget {
  final Object pulseKey;
  final Color? color;
  final double size;

  const MeasurementPulseIndicator({
    super.key,
    required this.pulseKey,
    this.color,
    this.size = 16,
  });

  @override
  State<MeasurementPulseIndicator> createState() => _MeasurementPulseIndicatorState();
}

class _MeasurementPulseIndicatorState extends State<MeasurementPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(covariant MeasurementPulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseKey != oldWidget.pulseKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Schnelles Einblenden (erste 15 % der Animationsdauer), danach
        // deutlich langsameres Ausblenden über die restlichen 85 % - ein
        // einzelner, gut wahrnehmbarer Impuls statt eines gleichmäßigen
        // Auf-und-Ab.
        final opacity = t <= 0.15 ? (t / 0.15) : (1 - (t - 0.15) / 0.85);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Icon(Icons.fiber_manual_record, size: widget.size, color: color),
        );
      },
    );
  }
}
