import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Info-Seite: Programmautor, App-Name, App-Version sowie ein Zugang zur
/// Übersicht aller verwendeten Module (Flutters eingebaute Lizenzseite).
/// Über den Info-Button in der App-Leiste von jeder der vier
/// Hauptseiten aus erreichbar (siehe HomeShell).
class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  static const _authorName = 'Claus J. Bauer';

  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    // PackageInfo.fromPlatform() darf laut Paket-Dokumentation nicht VOR
    // runApp() aufgerufen werden - hier (in initState einer bereits
    // laufenden Seite) ist das unproblematisch.
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _packageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;

    return Scaffold(
      appBar: AppBar(title: AutoHyphenatingText('Info')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.explore,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            AutoHyphenatingText(
              info?.appName ?? 'onTour',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              info != null
                  ? 'Version ${info.version} (Build ${info.buildNumber})'
                  : 'Version wird geladen …',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: AutoHyphenatingText('Programmautor'),
              subtitle: AutoHyphenatingText(_authorName),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            AutoHyphenatingText(
              'Diese App verwendet mehrere Open-Source-Module. Die '
              'jeweiligen Lizenztexte lassen sich hier einsehen:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: info?.appName ?? 'onTour',
                applicationVersion: info?.version,
                applicationLegalese: '© ${DateTime.now().year} $_authorName',
              ),
              icon: const Icon(Icons.description_outlined),
              label: AutoHyphenatingText('Verwendete Module'),
            ),
          ],
        ),
      ),
    );
  }
}
