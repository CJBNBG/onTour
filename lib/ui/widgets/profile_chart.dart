import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

/// Einfaches, selbst gezeichnetes Liniendiagramm mit gefüllter Fläche
/// unter der Kurve (klassische Höhenprofil-Optik) - verwendet für die vier
/// Profil-Diagramme auf dem Details-Tab von TrackPage/TrackDetailPage
/// (siehe README Abschnitt 29, TrackProfileCharts).
///
/// Bewusst als eigenes `CustomPaint`-Widget umgesetzt statt über ein
/// Chart-Paket als zusätzliche Abhängigkeit - passend zum bisherigen Stil
/// dieses Projekts, das großformatige, gestalterisch wichtige Anzeigen
/// grundsätzlich selbst zeichnet (siehe CompassDial,
/// SevenSegmentDisplay), inkl. der damit einhergehenden vollen Kontrolle
/// über Look & Feel (Theme-Farben, Dark Mode) ohne fremde Default-Optik.
class ProfileChart extends StatelessWidget {
  final String title;

  /// Die darzustellenden Punkte - `dx` = Distanz in km (x-Achse, allen vier
  /// Diagrammen gemeinsam, siehe TrackProfilePoint), `dy` = der jeweilige
  /// Messwert in der für dieses Diagramm gewählten Einheit. Punkte ohne
  /// verfügbaren Wert werden vom Aufrufer bereits vorab herausgefiltert
  /// (siehe TrackProfileCharts).
  final List<Offset> points;

  final Color color;

  /// Formatiert einen y-Wert für die Achsenbeschriftung, OHNE Einheit
  /// (die wird separat über [unit] angehängt) - z. B. "12,3" oder "-4".
  final String Function(double value) valueFormatter;

  /// Einheit, an die Achsenbeschriftungen angehängt wird, z. B. "km/h"
  /// oder "%".
  final String unit;

  /// true, wenn 0 als Referenzlinie eingezeichnet werden soll (sinnvoll
  /// bei Diagrammen, die auch negative Werte annehmen können - Anstieg,
  /// Steigung/Gefälle) - bei rein positiven Größen (Geschwindigkeit, Höhe)
  /// bewusst false, da die y-Achse dort ohnehin bei einem sinnvollen
  /// Minimum beginnt und eine erzwungene Null-Linie nur unnötig Platz
  /// verschwenden würde.
  final bool showZeroLine;

  final double height;

  const ProfileChart({
    super.key,
    required this.title,
    required this.points,
    required this.color,
    required this.valueFormatter,
    required this.unit,
    this.showZeroLine = false,
    this.height = 150,
  });

  static final intl.NumberFormat _distanceFormat = intl.NumberFormat('0.0', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: points.length < 2
              ? Center(
                  child: AutoHyphenatingText(
                    'Noch nicht genug Daten',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : CustomPaint(
                  painter: _ProfileChartPainter(
                    points: points,
                    lineColor: color,
                    gridColor: scheme.onSurface.withValues(alpha: 0.15),
                    labelColor: scheme.onSurfaceVariant,
                    valueFormatter: valueFormatter,
                    unit: unit,
                    showZeroLine: showZeroLine,
                    distanceLabelFormat: _distanceFormat,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProfileChartPainter extends CustomPainter {
  final List<Offset> points;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final String Function(double value) valueFormatter;
  final String unit;
  final bool showZeroLine;
  final intl.NumberFormat distanceLabelFormat;

  _ProfileChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.valueFormatter,
    required this.unit,
    required this.showZeroLine,
    required this.distanceLabelFormat,
  });

  /// Fester Platz links für die y-Achsen-Beschriftung (min-/max-Wert) -
  /// eine dynamische Breitenberechnung anhand der tatsächlichen Textlänge
  /// wäre zwar präziser, für die hier ohnehin kurzen Beschriftungen
  /// (wenige Ziffern plus Einheit) aber unnötiger Aufwand.
  static const double _yAxisLabelWidth = 80;
  static const double _bottomLabelHeight = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = Rect.fromLTWH(
      _yAxisLabelWidth,
      0,
      size.width - _yAxisLabelWidth,
      size.height - _bottomLabelHeight,
    );

    var minY = points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    var maxY = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    if (showZeroLine) {
      minY = minY > 0 ? 0 : minY;
      maxY = maxY < 0 ? 0 : maxY;
    }
    if (minY == maxY) {
      // Konstanter Verlauf (z. B. exakt gleichbleibende Höhe) - etwas
      // künstlichen Spielraum schaffen, sonst würde die Kurve auf eine
      // einzige Linie am oberen/unteren Rand kollabieren.
      minY -= 1;
      maxY += 1;
    }
    // Kleiner Rand ober-/unterhalb der Kurve, damit sie nicht exakt am
    // Diagrammrand klebt.
    final padding = (maxY - minY) * 0.08;
    minY -= padding;
    maxY += padding;

    final minX = points.first.dx;
    final maxX = points.last.dx;
    final xRange = (maxX - minX) == 0 ? 1.0 : (maxX - minX);
    final yRange = maxY - minY;

    Offset toCanvas(Offset p) {
      final normalizedX = (p.dx - minX) / xRange;
      final normalizedY = (p.dy - minY) / yRange;
      return Offset(
        plotRect.left + normalizedX * plotRect.width,
        plotRect.bottom - normalizedY * plotRect.height,
      );
    }

    _drawGridAndLabels(canvas, plotRect, minY, maxY);
    _drawCurve(canvas, plotRect, toCanvas);
    _drawDistanceLabels(canvas, plotRect, minX, maxX);
  }

  void _drawGridAndLabels(Canvas canvas, Rect plotRect, double minY, double maxY) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Drei horizontale Referenzlinien: oben (Maximum), Mitte, unten
    // (Minimum) - jeweils mit Wertebeschriftung links daneben.
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = plotRect.top + fraction * plotRect.height;
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);

      final value = maxY - fraction * (maxY - minY);
      _drawText(
        canvas,
        '${valueFormatter(value)} $unit',
        Offset(_yAxisLabelWidth - 6, y),
        alignRight: true,
        maxWidth: _yAxisLabelWidth - 6,
      );
    }

    // Zusätzliche, etwas kräftigere Null-Linie bei Diagrammen, die auch
    // negative Werte zeigen können (Anstieg, Steigung/Gefälle) - macht auf
    // einen Blick sichtbar, ob gerade auf- oder abwärts geht.
    if (showZeroLine && minY < 0 && maxY > 0) {
      final zeroY = plotRect.bottom - ((0 - minY) / (maxY - minY)) * plotRect.height;
      final zeroPaint = Paint()
        ..color = labelColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(plotRect.left, zeroY), Offset(plotRect.right, zeroY), zeroPaint);
    }
  }

  void _drawCurve(Canvas canvas, Rect plotRect, Offset Function(Offset) toCanvas) {
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final canvasPoint = toCanvas(points[i]);
      if (i == 0) {
        linePath.moveTo(canvasPoint.dx, canvasPoint.dy);
      } else {
        linePath.lineTo(canvasPoint.dx, canvasPoint.dy);
      }
    }

    // Gefüllte Fläche unter der Kurve bis zur Grundlinie (unterer
    // Diagrammrand) - klassische Höhenprofil-Optik.
    final fillPath = Path.from(linePath)
      ..lineTo(plotRect.right, plotRect.bottom)
      ..lineTo(plotRect.left, plotRect.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = lineColor.withValues(alpha: 0.18),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawDistanceLabels(Canvas canvas, Rect plotRect, double minX, double maxX) {
    // Vertikal mittig im unteren Beschriftungsstreifen (siehe
    // _bottomLabelHeight) platziert, NICHT direkt auf size.height - sonst
    // würde die untere Texthälfte außerhalb der Zeichenfläche liegen.
    final labelY = plotRect.bottom + _bottomLabelHeight / 2;
    _drawText(
      canvas,
      '${distanceLabelFormat.format(minX)} km',
      Offset(plotRect.left, labelY),
      alignRight: false,
      maxWidth: plotRect.width / 2,
    );
    _drawText(
      canvas,
      '${distanceLabelFormat.format(maxX)} km',
      Offset(plotRect.right, labelY),
      alignRight: true,
      maxWidth: plotRect.width / 2,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    required bool alignRight,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: labelColor, fontSize: 11)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final offset = alignRight ? Offset(anchor.dx - painter.width, anchor.dy - painter.height / 2) : Offset(anchor.dx, anchor.dy - painter.height / 2);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ProfileChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor || oldDelegate.showZeroLine != showZeroLine;
  }
}
