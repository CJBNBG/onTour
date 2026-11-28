import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';

/// Ein Eintrag der unteren Navigationsleiste.
class AppNavigationItem {
  final IconData icon;
  final String label;

  /// Optionaler kleiner Statuspunkt oben rechts am Symbol (z. B. roter
  /// Punkt bei laufender Aufzeichnung auf dem Karten-Tab). null = kein
  /// Punkt.
  final Color? badgeColor;

  /// Zusatztext für Screenreader, wenn ein [badgeColor] gesetzt ist
  /// (z. B. "Aufzeichnung läuft").
  final String? badgeLabel;

  const AppNavigationItem({
    required this.icon,
    required this.label,
    this.badgeColor,
    this.badgeLabel,
  });
}

/// Untere Navigationsleiste im Stil der Material-3-NavigationBar, aber mit
/// [AutoHyphenatingText] für die Beschriftungen (NavigationDestination
/// erlaubt dort nur einen String, siehe README Abschnitt 13) - lange
/// Wörter wie "Einstellungen" werden bei großer Systemschrift getrennt
/// statt abgeschnitten.
///
/// Bewusst OHNE IntrinsicHeight/-Width: AutoHyphenatingText nutzt einen
/// LayoutBuilder, der keine intrinsischen Berechnungen unterstützt.
class AppNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavigationItem> items;

  const AppNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.badgeColor != null && item.badgeLabel != null ? '${item.label}, ${item.badgeLabel}' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 64,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      item.icon,
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    ),
                    // Statuspunkt oben rechts am Symbol; der Rand in der
                    // Farbe der Leiste hebt ihn vom Symbol ab.
                    if (item.badgeColor != null)
                      Positioned(
                        top: 3,
                        right: 17,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: item.badgeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surfaceContainer, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: AutoHyphenatingText(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
