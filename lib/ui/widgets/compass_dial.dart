import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zeichnet eine dekorative Kompassrose, die sich passend zur aktuellen
/// Peilung [headingDegrees] dreht: Die Skala (samt Sternmuster und
/// Himmelsrichtungen) dreht sich entgegen der Peilung, so dass die
/// feststehende Spitze oben immer die tatsächliche Ausrichtung des
/// Geräts anzeigt (Funktionsprinzip eines klassischen Schiffskompasses
/// mit fester "Steuerstrich"-Marke).
///
/// Gestalterisch orientiert sich die Rose am App-Icon (roter/weißer
/// Zweiklang, siehe Nadel-Farben) und ergänzt: einen weichen Schlagschatten,
/// einen Verlaufshintergrund, einen mehrteiligen Rahmen ("Bezel"), ein
/// klassisches 8-zackiges Sternmuster sowie eine feine Grad-Skala mit
/// Haupt-/Zwischen-/Feinteilstrichen - statt der zuvor schlichten Version
/// mit nur vier beschrifteten Strichen.
class CompassDial extends StatelessWidget {
  final double headingDegrees;

  const CompassDial({super.key, required this.headingDegrees});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _CompassPainter(
          headingDegrees: headingDegrees,
          faceColor: scheme.surface,
          onFaceColor: scheme.onSurface,
          primaryColor: scheme.primary,
          roseColorA: scheme.primary,
          roseColorB: scheme.secondary,
          northColor: const Color(0xFFE53935), // klassisches Kompass-Rot
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double headingDegrees;
  final Color faceColor;
  final Color onFaceColor;
  final Color primaryColor;
  final Color roseColorA;
  final Color roseColorB;
  final Color northColor;

  _CompassPainter({
    required this.headingDegrees,
    required this.faceColor,
    required this.onFaceColor,
    required this.primaryColor,
    required this.roseColorA,
    required this.roseColorB,
    required this.northColor,
  });

  static const _directionLabels = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.88;

    _drawShadow(canvas, center, radius);
    _drawFace(canvas, center, radius);
    _drawBezel(canvas, center, radius);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Die Skala (Sternmuster, Teilstriche, Beschriftung) dreht sich
    // entgegen der Peilung - dadurch zeigt die feststehende Spitze oben
    // (siehe _drawHeadingPointer) stets die tatsächliche Blickrichtung des
    // Geräts, während "N" auf der Skala immer Richtung geografisch Nord
    // zeigt.
    canvas.rotate(-headingDegrees * math.pi / 180);

    _drawRoseStar(canvas, radius);
    _drawGraduation(canvas, radius);
    _drawDirectionLabels(canvas, radius);
    _drawHub(canvas, radius);

    canvas.restore();

    _drawGlossHighlight(canvas, center, radius);
    _drawHeadingPointer(canvas, center, radius);
  }

  /// Weicher Schlagschatten unter der Rose - verleiht Tiefe.
  void _drawShadow(Canvas canvas, Offset center, double radius) {
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center.translate(0, radius * 0.05), radius, shadowPaint);
  }

  /// Zifferblatt mit dezentem Verlauf (Mitte heller, Rand etwas dunkler).
  void _drawFace(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final facePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          faceColor,
          Color.lerp(faceColor, onFaceColor, 0.08)!,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, facePaint);
  }

  /// Mehrteiliger, dekorativer Rahmen ("Bezel") um das Zifferblatt.
  void _drawBezel(Canvas canvas, Offset center, double radius) {
    final outerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.045
      ..shader = SweepGradient(
        colors: [
          primaryColor,
          Color.lerp(primaryColor, Colors.white, 0.5)!,
          primaryColor,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, outerRing);

    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.012
      ..color = onFaceColor.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius * 0.86, innerRing);
  }

  /// Klassisches, mehrzackiges Sternmuster einer Kompassrose - abwechselnd
  /// lange (Haupt-) und kurze (Zwischen-)Zacken in zwei Tönen.
  void _drawRoseStar(Canvas canvas, double radius) {
    const points = 8;
    final longPaint = Paint()..color = roseColorA.withValues(alpha: 0.16);
    final shortPaint = Paint()..color = roseColorB.withValues(alpha: 0.12);

    for (var i = 0; i < points; i++) {
      final angle = i * (360 / points) * math.pi / 180;
      final nextAngle = (i + 0.5) * (360 / points) * math.pi / 180;
      final prevAngle = (i - 0.5) * (360 / points) * math.pi / 180;

      final tip = Offset(radius * 0.82 * math.sin(angle), -radius * 0.82 * math.cos(angle));
      final left = Offset(
          radius * 0.22 * math.sin(prevAngle), -radius * 0.22 * math.cos(prevAngle));
      final right = Offset(
          radius * 0.22 * math.sin(nextAngle), -radius * 0.22 * math.cos(nextAngle));

      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(left.dx, left.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(path, i.isEven ? longPaint : shortPaint);
    }
  }

  /// Feine Grad-Skala: Hauptstriche alle 45° (an den Himmelsrichtungen),
  /// mittlere Striche alle 15°, feine Striche alle 5° - wirkt wie eine
  /// echte, präzise graduierte Kompassrose statt nur vier grober Striche.
  void _drawGraduation(Canvas canvas, double radius) {
    for (var degree = 0; degree < 360; degree += 5) {
      final isMajor = degree % 45 == 0;
      final isMedium = !isMajor && degree % 15 == 0;
      final lengthRatio = isMajor ? 0.16 : (isMedium ? 0.10 : 0.05);
      final strokeWidth = isMajor ? radius * 0.02 : (isMedium ? radius * 0.012 : radius * 0.006);
      final opacity = isMajor ? 0.9 : (isMedium ? 0.6 : 0.35);

      final angle = degree * math.pi / 180;
      final outer = Offset(radius * 0.86 * math.sin(angle), -radius * 0.86 * math.cos(angle));
      final inner = Offset(
        radius * (0.86 - lengthRatio) * math.sin(angle),
        -radius * (0.86 - lengthRatio) * math.cos(angle),
      );

      final tickPaint = Paint()
        ..color = (degree == 0 ? northColor : onFaceColor).withValues(alpha: opacity)
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  void _drawDirectionLabels(Canvas canvas, double radius) {
    for (var i = 0; i < _directionLabels.length; i++) {
      final degree = i * 45.0;
      final isNorth = i == 0;
      final isCardinal = i.isEven; // N, O, S, W etwas betonter als NO/SO/SW/NW

      final angle = degree * math.pi / 180;
      final textPainter = TextPainter(
        text: TextSpan(
          text: _directionLabels[i],
          style: TextStyle(
            color: isNorth ? northColor : onFaceColor.withValues(alpha: isCardinal ? 1 : 0.75),
            fontSize: isNorth ? radius * 0.20 : (isCardinal ? radius * 0.15 : radius * 0.11),
            fontWeight: isNorth || isCardinal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRadius = radius * 0.62;
      final offset = Offset(
        labelRadius * math.sin(angle) - textPainter.width / 2,
        -labelRadius * math.cos(angle) - textPainter.height / 2,
      );
      textPainter.paint(canvas, offset);
    }
  }

  /// Mittlere Nabe mit kleinem Glanzpunkt.
  void _drawHub(Canvas canvas, double radius) {
    final hubRadius = radius * 0.09;
    final hubPaint = Paint()
      ..shader = RadialGradient(
        colors: [Color.lerp(primaryColor, Colors.white, 0.6)!, primaryColor],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: hubRadius));
    canvas.drawCircle(Offset.zero, hubRadius, hubPaint);
    canvas.drawCircle(
      Offset.zero,
      hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hubRadius * 0.18
        ..color = onFaceColor.withValues(alpha: 0.4),
    );
  }

  /// Dezenter Glanzstreifen über dem oberen Drittel der Rose (Glaseffekt),
  /// NACH der Skala, aber VOR der festen Peilungs-Spitze gezeichnet.
  void _drawGlossHighlight(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final path = Path()..addOval(rect);
    canvas.save();
    canvas.clipPath(path);
    final glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawRect(rect, glossPaint);
    canvas.restore();
  }

  /// Feststehende Spitze oben - repräsentiert die tatsächliche
  /// Ausrichtung/Blickrichtung des Geräts (klassischer "Steuerstrich").
  void _drawHeadingPointer(Canvas canvas, Offset center, double radius) {
    final tipY = center.dy - radius - radius * 0.16;
    final baseY = center.dy - radius + radius * 0.06;
    final halfWidth = radius * 0.09;

    final pointerPaint = Paint()..color = northColor;
    final pointerPath = Path()
      ..moveTo(center.dx, tipY)
      ..lineTo(center.dx - halfWidth, baseY)
      ..lineTo(center.dx + halfWidth, baseY)
      ..close();
    canvas.drawPath(pointerPath, pointerPaint);

    // Kleiner runder Kopf an der Spitze für einen "Stecknadel"-Touch.
    canvas.drawCircle(Offset(center.dx, tipY), halfWidth * 0.45, pointerPaint);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.headingDegrees != headingDegrees;
}
