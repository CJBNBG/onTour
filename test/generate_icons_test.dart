// Erzeugt die drei Launcher-Icon-Dateien für onTour (je 1024x1024 px):
//   assets/icon/icon_background.png  - einfarbig Teal
//   assets/icon/icon_foreground.png  - nur das Motiv, transparent, verkleinert
//   assets/icon/icon.png             - Hintergrund + Motiv
//
// Ausführen (im Projektordner):
//   flutter test test/generate_icons_test.dart
//
// Danach:
//   dart run flutter_launcher_icons

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 1024;
const Color _teal = Color(0xFF0F766E);
const Color _red = Color(0xFFE53935);
const Color _amber = Color(0xFFFFB300);

/// Zeichnet das Motiv in einem 200x200-Koordinatensystem, mittig im Bild.
/// [scale] bestimmt die Größe (5,12 = volle Bildbreite).
void _drawMotif(Canvas canvas, double scale) {
  canvas.save();
  canvas.translate(_size / 2, _size / 2);
  canvas.scale(scale);
  canvas.translate(-100, -100);

  const center = Offset(100, 100);

  // Kompassring
  canvas.drawCircle(
    center,
    68,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8,
  );

  // Vier Striche (N, O, S, W)
  final tick = Paint()
    ..color = Colors.white
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(const Offset(100, 22), const Offset(100, 38), tick);
  canvas.drawLine(const Offset(100, 162), const Offset(100, 178), tick);
  canvas.drawLine(const Offset(22, 100), const Offset(38, 100), tick);
  canvas.drawLine(const Offset(162, 100), const Offset(178, 100), tick);

  // Nadel: rote Spitze = Norden, weiße Spitze = Süden
  canvas.drawPath(
    Path()
      ..moveTo(100, 44)
      ..lineTo(86, 100)
      ..lineTo(114, 100)
      ..close(),
    Paint()..color = _red,
  );
  canvas.drawPath(
    Path()
      ..moveTo(100, 156)
      ..lineTo(86, 100)
      ..lineTo(114, 100)
      ..close(),
    Paint()..color = Colors.white,
  );

  // Nabe
  canvas.drawCircle(center, 8, Paint()..color = _teal);
  canvas.drawCircle(
    center,
    8,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  // Gelber Zielpunkt am Ring
  canvas.drawCircle(const Offset(148, 52), 13, Paint()..color = _amber);
  canvas.drawCircle(
    const Offset(148, 52),
    13,
    Paint()
      ..color = _teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );

  canvas.restore();
}

Future<void> _save(String fileName, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);

  final dir = Directory('assets/icon');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('assets/icon/$fileName').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('Launcher-Icons erzeugen', (tester) async {
    await tester.runAsync(() async {
      final fullRect = Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble());

      // Hintergrund-Ebene (Adaptive Icons)
      await _save('icon_background.png', (c) {
        c.drawRect(fullRect, Paint()..color = _teal);
      });

      // Vordergrund-Ebene: Motiv bewusst kleiner (3,9), damit es innerhalb
      // der "sicheren Zone" bleibt und von runden Launcher-Masken nicht
      // abgeschnitten wird.
      await _save('icon_foreground.png', (c) => _drawMotif(c, 3.9));

      // Vollbild-Icon (auch für die Info-Seite)
      await _save('icon.png', (c) {
        c.drawRect(fullRect, Paint()..color = _teal);
        _drawMotif(c, 4.6);
      });
    });
  });
}
