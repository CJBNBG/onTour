import 'package:flutter/material.dart';

/// Label für [ButtonSegment]s mit dem Symbol OBERHALB des Textes -
/// dadurch bleibt der Text auch bei schmalen Displays einzeilig, was
/// bei der üblichen Anordnung (Symbol neben dem Text) nicht garantiert
/// ist. Statt des `icon`-Parameters von ButtonSegment als `label`
/// verwenden und am SegmentedButton `showSelectedIcon: false` setzen,
/// da sonst ein zusätzliches Häkchen Platz beansprucht.
///
/// Bewusst normales [Text] (kein AutoHyphenatingText): SegmentedButton
/// berechnet intrinsische Breiten, siehe README Abschnitt 13.
class StackedSegmentLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const StackedSegmentLabel({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 2),
        Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
      ],
    );
  }
}
