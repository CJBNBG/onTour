import 'package:flutter/material.dart';

/// Stellt eine Zeichenkette (Ziffern sowie Komma als Dezimaltrennzeichen)
/// als klassische rote Sieben-Segment-Anzeige dar - vollständig als Vektor-
/// grafik gezeichnet (kein Font-Asset nötig, daher lizenzfrei einsetzbar).
///
/// Wie bei den übrigen großformatigen Anzeigen in diesem Projekt (siehe
/// z. B. CompassDial) besitzt dieses Widget eine feste, aus [height]
/// abgeleitete Eigengröße - der Aufrufer skaliert es üblicherweise über
/// ein umgebendes `FittedBox`, damit es den verfügbaren Platz optimal
/// ausfüllt.
class SevenSegmentDisplay extends StatelessWidget {
  final String text;
  final Color color;
  final double height;

  const SevenSegmentDisplay({
    super.key,
    required this.text,
    this.color = const Color(0xFFFF1E1E),
    this.height = 160,
  });

  /// Breite einer normalen Ziffernzelle im Verhältnis zur Höhe - an
  /// klassischen Sieben-Segment-Anzeigen orientiert.
  static const double _digitWidthRatio = 0.62;

  /// Breite der (schmaleren) Zelle für das Komma.
  static const double _commaWidthRatio = 0.28;

  double get _totalWidth {
    var width = 0.0;
    for (final char in text.split('')) {
      width += (char == ',' || char == '.')
          ? height * _commaWidthRatio
          : height * _digitWidthRatio;
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(_totalWidth, height),
      painter: _SevenSegmentPainter(text: text, color: color),
    );
  }
}

/// Segment-Belegung je Ziffer (a=oben, b=oben-rechts, c=unten-rechts,
/// d=unten, e=unten-links, f=oben-links, g=Mitte) - Standard-Zuordnung
/// einer Sieben-Segment-Anzeige.
const Map<String, List<bool>> _digitSegments = {
  // Reihenfolge je Eintrag: [a, b, c, d, e, f, g]
  '0': [true, true, true, true, true, true, false],
  '1': [false, true, true, false, false, false, false],
  '2': [true, true, false, true, true, false, true],
  '3': [true, true, true, true, false, false, true],
  '4': [false, true, true, false, false, true, true],
  '5': [true, false, true, true, false, true, true],
  '6': [true, false, true, true, true, true, true],
  '7': [true, true, true, false, false, false, false],
  '8': [true, true, true, true, true, true, true],
  '9': [true, true, true, true, false, true, true],
  '-': [false, false, false, false, false, false, true],
};

class _SevenSegmentPainter extends CustomPainter {
  final String text;
  final Color color;

  _SevenSegmentPainter({required this.text, required this.color});

  static const double _digitWidthRatio = SevenSegmentDisplay._digitWidthRatio;
  static const double _commaWidthRatio = SevenSegmentDisplay._commaWidthRatio;

  @override
  void paint(Canvas canvas, Size size) {
    var x = 0.0;
    for (final char in text.split('')) {
      if (char == ',' || char == '.') {
        final cellWidth = size.height * _commaWidthRatio;
        _paintComma(canvas, Offset(x, 0), cellWidth, size.height);
        x += cellWidth;
      } else {
        final cellWidth = size.height * _digitWidthRatio;
        _paintDigit(canvas, Offset(x, 0), cellWidth, size.height, char);
        x += cellWidth;
      }
    }
  }

  void _paintDigit(Canvas canvas, Offset origin, double w, double h, String char) {
    final segments = _digitSegments[char];
    // Unbekannte Zeichen (sollte praktisch nicht vorkommen, da
    // SpeedFormatter nur Ziffern und ein Komma liefert) werden einfach als
    // leere Zelle (nur "Geister"-Segmente) dargestellt.
    _paintSevenSegmentCell(canvas, origin, w, h, segments);
  }

  void _paintSevenSegmentCell(
    Canvas canvas,
    Offset origin,
    double w,
    double h,
    List<bool>? segments,
  ) {
    final padding = w * 0.16;
    final usableW = w - 2 * padding;
    final usableH = h - 2 * padding;
    final halfH = usableH / 2;
    final thickness = usableW * 0.32;

    final left = origin.dx + padding;
    final top = origin.dy + padding;

    final onPaint = Paint()..color = color;
    // Stark abgeschwächte "Geister"-Segmente (kaum sichtbarer Rest-Kontrast
    // zum Hintergrund) - bewusst deutlich dezenter als ein reguläres
    // unbeleuchtetes Segment auf echten Digitalanzeigen.
    final offPaint = Paint()..color = color.withValues(alpha: 0.015);

    // Reihenfolge a, b, c, d, e, f, g.
    final segmentPaths = <Path>[
      _hSegment(left + usableW / 2, top, usableW, thickness), // a: oben
      _vSegment(left + usableW, top + halfH / 2, halfH, thickness), // b: oben rechts
      _vSegment(left + usableW, top + halfH + halfH / 2, halfH, thickness), // c: unten rechts
      _hSegment(left + usableW / 2, top + usableH, usableW, thickness), // d: unten
      _vSegment(left, top + halfH + halfH / 2, halfH, thickness), // e: unten links
      _vSegment(left, top + halfH / 2, halfH, thickness), // f: oben links
      _hSegment(left + usableW / 2, top + halfH, usableW, thickness), // g: Mitte
    ];

    for (var i = 0; i < segmentPaths.length; i++) {
      final isOn = segments != null && segments[i];
      canvas.drawPath(segmentPaths[i], isOn ? onPaint : offPaint);
    }
  }

  void _paintComma(Canvas canvas, Offset origin, double w, double h) {
    final padding = h * 0.16;
    final dotSize = w * 0.5;
    final onPaint = Paint()..color = color;
    // Das Komma sitzt - wie bei realen Digitalanzeigen üblich - unten in
    // der Zelle, auf Höhe der unteren Grundlinie der Ziffern.
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy + h - padding - dotSize,
      dotSize,
      dotSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(dotSize * 0.2)),
      onPaint,
    );
  }

  /// Horizontales Segment (sechseckige Form mit angeschrägten Enden) mit
  /// Mittelpunkt [cx]/[cy], Länge [length] und Dicke [thickness].
  Path _hSegment(double cx, double cy, double length, double thickness) {
    final halfLen = length / 2;
    final halfThick = thickness / 2;
    return Path()
      ..moveTo(cx - halfLen, cy)
      ..lineTo(cx - halfLen + halfThick, cy - halfThick)
      ..lineTo(cx + halfLen - halfThick, cy - halfThick)
      ..lineTo(cx + halfLen, cy)
      ..lineTo(cx + halfLen - halfThick, cy + halfThick)
      ..lineTo(cx - halfLen + halfThick, cy + halfThick)
      ..close();
  }

  /// Vertikales Segment, analog zu [_hSegment], aber um 90° gedreht.
  Path _vSegment(double cx, double cy, double length, double thickness) {
    final halfLen = length / 2;
    final halfThick = thickness / 2;
    return Path()
      ..moveTo(cx, cy - halfLen)
      ..lineTo(cx + halfThick, cy - halfLen + halfThick)
      ..lineTo(cx + halfThick, cy + halfLen - halfThick)
      ..lineTo(cx, cy + halfLen)
      ..lineTo(cx - halfThick, cy + halfLen - halfThick)
      ..lineTo(cx - halfThick, cy - halfLen + halfThick)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _SevenSegmentPainter oldDelegate) =>
      oldDelegate.text != text || oldDelegate.color != color;
}
