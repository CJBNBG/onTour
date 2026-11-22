import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/app_preferences.dart';
import '../../services/camping_data_service.dart';

/// Abschnitt "Camping-Daten" mit Datenstand und Aktualisieren-Button, der
/// höchstens einmal pro Kalendertag gedrückt werden kann (nur nach einem
/// erfolgreichen Update gesperrt).
class CampingDataSection extends StatefulWidget {
  final AppPreferences preferences;

  const CampingDataSection({super.key, required this.preferences});

  @override
  State<CampingDataSection> createState() => _CampingDataSectionState();
}

class _CampingDataSectionState extends State<CampingDataSection> {
  final CampingDataService _service = CampingDataService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.loadDataDate();
  }

  bool get _updatedToday {
    final last = widget.preferences.campingLastUpdateAt;
    if (last == null) return false;
    final now = DateTime.now();
    return last.year == now.year && last.month == now.month && last.day == now.day;
  }

  Future<void> _update() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      await _service.updateFromServer();
      await widget.preferences.setCampingLastUpdateAt(DateTime.now());
      message = 'Camping-Daten aktualisiert (Stand ${_service.dataDateText}).';
    } on CampingUpdateException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Die Aktualisierung ist fehlgeschlagen.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_service, widget.preferences]),
      builder: (context, _) {
        final String label;
        if (_busy) {
          label = 'Lädt …';
        } else if (_updatedToday) {
          label = 'Heute bereits aktualisiert';
        } else {
          label = 'Jetzt aktualisieren';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoHyphenatingText('Camping-Daten', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              'Stand: ${_service.dataDateText}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              'Die Daten werden täglich neu erzeugt. Eine Aktualisierung lädt '
              'ca. 3-4 MB und ist einmal pro Tag möglich.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // Bewusst normales Text-Widget im Button (siehe README Abschnitt 13).
            FilledButton.tonalIcon(
              onPressed: (_busy || _updatedToday) ? null : _update,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(label),
            ),
          ],
        );
      },
    );
  }
}
