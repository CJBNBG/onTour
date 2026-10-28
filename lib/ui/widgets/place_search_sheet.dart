import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';

import '../../models/place_result.dart';
import '../../services/place_search_service.dart';

/// Inhalt des Bottom Sheets zur Ortssuche (siehe README Abschnitt 50):
/// Suchfeld, Ergebnisliste und Quellenangabe. Wird über
/// `showModalBottomSheet<PlaceResult>` geöffnet und liefert per
/// `Navigator.pop` den gewählten Ort zurück (null bei Abbruch).
///
/// Gesucht wird bewusst NUR auf ausdrücklichen Befehl (Tastatur-"Suchen"
/// bzw. Lupen-Button), nicht bei jeder Eingabe - die Nutzungsbedingungen
/// des öffentlichen Nominatim-Servers untersagen Autovervollständigung
/// (siehe PlaceSearchService).
class PlaceSearchSheet extends StatefulWidget {
  final PlaceSearchService service;

  const PlaceSearchSheet({super.key, required this.service});

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final TextEditingController _controller = TextEditingController();

  List<PlaceResult> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2 || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.service.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
        _loading = false;
      });
    } on PlaceSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _results = const [];
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Die Suche ist fehlgeschlagen.';
        _results = const [];
        _searched = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Padding(
      // Hebt das Sheet über die Bildschirmtastatur.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoHyphenatingText('Ort suchen', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Ort, Adresse oder Sehenswürdigkeit',
                    suffixIcon: IconButton(
                      tooltip: 'Suchen',
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: AutoHyphenatingText(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  )
                else if (_searched && _results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    // Bewusst normales Text-Widget (kurze Meldung).
                    child: Text('Keine Treffer. Versuche eine andere Schreibweise.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final place = _results[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            place.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(place),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                // Quellenangabe (Nutzungsbedingungen von Nominatim/OSM).
                Text(
                  'Suchergebnisse: © OpenStreetMap-Mitwirkende (Nominatim)',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
