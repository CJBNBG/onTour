import 'package:url_launcher/url_launcher.dart';

/// Öffnet [url] im externen Browser. Fehler (kein Browser, ungültige URL)
/// werden bewusst verschluckt - ein Link ist ein reiner Komfort-Zusatz.
Future<void> openExternalLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Siehe Methodenkommentar.
  }
}
