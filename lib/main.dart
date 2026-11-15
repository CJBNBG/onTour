import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'services/app_preferences.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Anforderung: Es wird nur das Hochkantformat genutzt.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Lädt die Trennmuster für die automatische Silbentrennung (deutsche
  // Rechtschreibung nach der Reform von 1996) - wird von AutoHyphenatingText
  // überall im Projekt verwendet (siehe Text-Ausgaben in lib/ui/).
  await initHyphenation(DefaultResourceLoaderLanguage.de1996);

  // WICHTIG: Lädt die deutschen Locale-Daten für DateFormat (Paket intl).
  // Anders als NumberFormat (bereits an mehreren Stellen im Projekt mit
  // 'de_DE' im Einsatz, z. B. speed_formatter.dart/compass_page.dart, und
  // dort OHNE gesonderte Initialisierung nutzbar) benötigt DateFormat für
  // jede Locale außer der eingebauten Minimalausstattung eine explizite
  // Initialisierung - ohne diesen Aufruf wirft jeder DateFormat(...,
  // 'de_DE')-Aufruf zur Laufzeit eine LocaleDataException. Erstmals
  // verwendet in util/track_formatter.dart (Datumsanzeige eines Tracks) -
  // ohne diese Zeile bliebe z. B. der "Aufzeichnung beenden"-Dialog auf
  // der Track-Seite wirkungslos, da TrackFormatter.suggestName() (intern
  // ein DateFormat) dort als Erstes aufgerufen wird und die Exception
  // in einem Button-Callback ansonsten unsichtbar verpufft.
  await initializeDateFormatting('de_DE');

  final preferences = AppPreferences();
  await preferences.load();

  runApp(OnTourApp(preferences: preferences));
}

class OnTourApp extends StatelessWidget {
  final AppPreferences preferences;

  const OnTourApp({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder sorgt dafür, dass sich Anzeigemodus-Änderungen aus
    // der Einstellungsseite sofort auf die gesamte App auswirken.
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        return MaterialApp(
          title: 'onTour',
          themeMode: preferences.themeMode,
          theme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          home: HomeShell(preferences: preferences),
        );
      },
    );
  }
}
