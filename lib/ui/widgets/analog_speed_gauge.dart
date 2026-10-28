import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Analoges Rundinstrument für die Geschwindigkeit: 270°-Skala (von
/// unten links über oben nach unten rechts), Zeiger mit weicher
/// Nachführung, farbiger Fortschrittsbogen und - da ein Zeiger kaum auf
/// 0,1 genau ablesbar ist - der Zahlenwert klein im unteren Teil des
/// Zifferblatts.
///
/// Kennt keine Einheitenumrechnung: [value] und [maxValue] müssen bereits
/// in der Anzeigeeinheit vorliegen. Überschreitet [value] das Skalenende,
/// bleibt der Zeiger am Anschlag.
class AnalogSpeedGauge extends StatelessWidget {
  final double value;
  final int maxValue;
  final String valueText;
  final String unitSymbol;

  const AnalogSpeedGauge({
    super.key,
    required this.value,
    required this.maxValue,
    required this.valueText,
    required this.unitSymbol,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = value.isFinite ? value.clamp(0, maxValue.toDouble()).toDouble() : 0.0;

    return AspectRatio(
      aspectRatio: 1,
      // Glättet die ruckartig (ca. 1x pro Sekunde) eintreffenden GPS-Werte:
      // Der Tween startet bei jeder Änderung vom aktuell angezeigten Wert.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.shortestSide;
              return Stack(
                children: [
                  CustomPaint(
                    size: Size.square(size),
                    painter: _GaugePainter(
                      value: animated,
                      maxValue: maxValue,
                      faceColor: scheme.surface,
                      onFaceColor: scheme.onSurface,
                      accentColor: scheme.primary,
                      needleColor: const Color(0xFFE53935),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.62),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          valueText,
                          style: TextStyle(
                            fontSize: size * 0.13,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          unitSymbol,
                          style: TextStyle(
                            fontSize: size * 0.07,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final int maxValue;
  final Color faceColor;
  final Color onFaceColor;
  final Color accentColor;
  final Color needleColor;

  _GaugePainter({
    required this.value,
    required this.maxValue,
    required this.faceColor,
    required this.onFaceColor,
    required this.accentColor,
    required this.needleColor,
  });

  /// Skalenbeginn (Canvas-Winkel, 0° = rechts, im Uhrzeigersinn): unten
  /// links; die Skala überstreicht 270° bis unten rechts.
  static const double _startAngle = 135 * math.pi / 180;
  static const double _sweepAngle = 270 * math.pi / 180;

  double _angleFor(double v) => _startAngle + _sweepAngle * (v / maxValue);

  Offset _point(Offset center, double radius, double angle) =>
      center + Offset(math.cos(angle), math.sin(angle)) * radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.95;

    // Zifferblatt
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [faceColor, Color.lerp(faceColor, onFaceColor, 0.08)!],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.03
        ..color = accentColor,
    );

    // Fortschrittsbogen unter dem Zeiger
    final arcRadius = radius * 0.80;
    final arcRect = Rect.fromCircle(center: center, radius: arcRadius);
    canvas.drawArc(
      arcRect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.05
        ..color = onFaceColor.withValues(alpha: 0.08),
    );
    if (value > 0) {
      canvas.drawArc(
        arcRect,
        _startAngle,
        _sweepAngle * (value / maxValue),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.05
          ..strokeCap = StrokeCap.round
          ..color = accentColor.withValues(alpha: 0.55),
      );
    }

    _drawTicksAndLabels(canvas, center, radius);
    _drawNeedle(canvas, center, radius);
  }

  void _drawTicksAndLabels(Canvas canvas, Offset center, double radius) {
    // 5 Hauptintervalle bei Skalenende 5, sonst 10; je 5 Feinteilungen.
    final majorCount = maxValue == 5 ? 5 : 10;
    final majorStep = maxValue / majorCount;
    const minorPerMajor = 5;

    for (var i = 0; i <= majorCount * minorPerMajor; i++) {
      final isMajor = i % minorPerMajor == 0;
      final v = i * majorStep / minorPerMajor;
      final angle = _angleFor(v);
      final outer = _point(center, radius * 0.72, angle);
      final inner = _point(center, radius * (isMajor ? 0.60 : 0.66), angle);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = onFaceColor.withValues(alpha: isMajor ? 0.9 : 0.45)
          ..strokeWidth = isMajor ? radius * 0.02 : radius * 0.008
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final painter = TextPainter(
          text: TextSpan(
            text: v.round().toString(),
            style: TextStyle(
              color: onFaceColor,
              fontSize: radius * (majorCount == 10 ? 0.11 : 0.13),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = _point(center, radius * 0.47, angle);
        painter.paint(canvas, p - Offset(painter.width / 2, painter.height / 2));
      }
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius) {
    final angle = _angleFor(value);
    final tip = _point(center, radius * 0.74, angle);
    final tail = _point(center, radius * 0.12, angle + math.pi);
    final perp = angle + math.pi / 2;
    final halfWidth = radius * 0.035;
    final left = center + Offset(math.cos(perp), math.sin(perp)) * halfWidth;
    final right = center - Offset(math.cos(perp), math.sin(perp)) * halfWidth;

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(tail.dx, tail.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = needleColor,
    );
    canvas.drawCircle(center, radius * 0.07, Paint()..color = onFaceColor.withValues(alpha: 0.85));
    canvas.drawCircle(center, radius * 0.03, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.maxValue != maxValue ||
      old.faceColor != faceColor ||
      old.accentColor != accentColor;
}
