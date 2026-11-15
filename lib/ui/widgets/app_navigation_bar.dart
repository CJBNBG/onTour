import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';

/// Ein Eintrag der unteren Navigationsleiste.
class AppNavigationItem {
  final IconData icon;
  final String label;

  const AppNavigationItem({required this.icon, required this.label});
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
      label: item.label,
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
                child: Icon(
                  item.icon,
                  color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
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
