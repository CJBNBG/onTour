import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../services/app_preferences.dart';
import '../util/navigation_notice.dart';

/// Zeigt den Hinweis "keine Navigation" (README Abschnitt 70) als Dialog,
/// der sich nicht wegtippen lässt (kein Tippen daneben, keine
/// Zurück-Taste): Er verschwindet erst, wenn der Nutzer ausdrücklich
/// bestätigt, ihn gelesen und verstanden zu haben - die Bestätigung wird
/// gespeichert ([AppPreferences.acceptNavigationNotice]). Alternativ lässt
/// sich die App beenden. Aufgerufen von HomeShell beim Start, solange
/// [AppPreferences.navigationNoticeAccepted] falsch ist.
Future<void> showNavigationNoticeDialog(BuildContext context, AppPreferences preferences) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: _NavigationNoticeDialog(preferences: preferences),
    ),
  );
}

class _NavigationNoticeDialog extends StatefulWidget {
  final AppPreferences preferences;

  const _NavigationNoticeDialog({required this.preferences});

  @override
  State<_NavigationNoticeDialog> createState() => _NavigationNoticeDialogState();
}

class _NavigationNoticeDialogState extends State<_NavigationNoticeDialog> {
  bool _confirmed = false;

  Future<void> _accept() async {
    await widget.preferences.acceptNavigationNotice();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Bewusst normale Text-Widgets statt AutoHyphenatingText: in einem
    // AlertDialog führt dessen LayoutBuilder zu Fehlern bei der
    // intrinsischen Breitenberechnung (siehe README Abschnitt 13).
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.warning_amber_rounded, size: 36, color: theme.colorScheme.error),
      title: const Text(NavigationNotice.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final paragraph in NavigationNotice.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(paragraph),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value ?? false),
            title: Text(
              NavigationNotice.confirmation,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => SystemNavigator.pop(),
          child: const Text('App beenden'),
        ),
        FilledButton(
          onPressed: _confirmed ? _accept : null,
          child: const Text('Verstanden'),
        ),
      ],
    );
  }
}
