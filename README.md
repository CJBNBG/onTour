# onTour

Flutter-App (Android) mit vier Ansichten (Tacho / Kompass / Track /
Einstellungen), erreichbar über eine untere Navigationsleiste. Die
Geschwindigkeitsanzeige ("Tacho") ist die Hauptfunktion und nimmt bewusst
den größten Teil des Bildschirms ein.

**Hinweis:** Die App zielt bewusst ausschließlich auf Android - es gibt
keine iOS-Konfiguration und keine iOS-spezifischen Anpassungen.

## 1. Projekt anlegen und Dateien übernehmen

Da dieses Paket nur den Dart-Code (`lib/`), `pubspec.yaml` sowie eine
native Android-Ergänzung enthält (kein fertiges `flutter create`-Grundgerüst,
da das plattformabhängige Boilerplate am besten direkt mit deiner
installierten Flutter-Version erzeugt wird), gehst du so vor:

```bash
flutter create --platforms=android --org de.clausjbauer --project-name ontour .
```

(`--platforms=android` erzeugt bewusst NUR den `android/`-Ordner, kein
`ios/` - passend dazu, dass die App ausschließlich auf Android läuft.)

Das erzeugt u. a. `android/` sowie eine Standard-`lib/main.dart`. Kopiere
anschließend den kompletten Inhalt des hier gelieferten `lib/`-Ordners in
dein Projekt (die generierte `lib/main.dart` wird dabei überschrieben) und
übernimm die Abhängigkeiten aus der gelieferten `pubspec.yaml` in deine
`pubspec.yaml`. Danach:

```bash
flutter pub get
```

**Hinweis zu Paketversionen:** Die in `pubspec.yaml` verwendeten
Versionsuntergrenzen (`^`) wurden nach bestem Wissen aktuell gewählt,
können sich aber naturgemäß seit Erstellung dieses Projekts weiterentwickelt
haben. Führe bei Bedarf `flutter pub outdated` aus, um zu prüfen, ob
neuere kompatible Versionen verfügbar sind.

**Wichtig:** Der obige `flutter create`-Befehl erzeugt die applicationId
`de.clausjbauer.ontour`. Wenn du einen anderen Org-/Projektnamen verwendest,
muss die `package`-Zeile in der weiter unten beschriebenen
`MainActivity.kt` entsprechend angepasst werden (sowie deren Pfad im
Projekt) - siehe Abschnitt 3.

## 2. Android-Konfiguration (android/app/src/main/AndroidManifest.xml)

Innerhalb von `<manifest>`, aber außerhalb von `<application>`, ergänzen:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

`INTERNET` wird für das Laden der Kartenkacheln (OpenStreetMap/OpenSeaMap)
benötigt, die beiden Standort-Berechtigungen für Tacho, Track und die
Satellitenanzahl. Für den Beschleunigungssensor (Stillstandserkennung,
Abschnitt 6) ist unter Android KEINE gesonderte Berechtigung nötig.

`minSdkVersion` sollte auf mindestens 21 stehen (Standard bei aktuellen
Flutter-Projekten bereits der Fall).

## 3. Satellitenanzahl (natives Android-Modul)

Die Anzahl der für den Positions-Fix verwendeten Satelliten ist nur über
die Android-eigene GNSS-Status-API abrufbar - dafür liegt in diesem Paket
zusätzlich `native_android/de/clausjbauer/ontour/MainActivity.kt` bei (der
Ordnerpfad unter `native_android/` spiegelt bewusst exakt den Zielpfad im
generierten Projekt). Diese Datei ersetzt die von `flutter create`
generierte `android/app/src/main/kotlin/de/clausjbauer/ontour/MainActivity.kt`
1:1 - am einfachsten kopierst du den kompletten Inhalt von
`native_android/de/` nach `android/app/src/main/kotlin/de/` und
überschreibst die dort bereits vorhandene `MainActivity.kt`.

(Pfad entspricht der oben verwendeten applicationId - bei abweichendem
Org-/Projektnamen Pfad UND die `package`-Zeile in der Datei entsprechend
anpassen.)

Ohne diesen Schritt läuft die App weiterhin einwandfrei - die
Satellitenanzahl wird dann einfach dauerhaft als "nicht verfügbar"
angezeigt (siehe `lib/services/satellite_service.dart`).

## 4. Genauigkeit/Aktualität der Geschwindigkeitsmessung (Einstellungen)

Auf der Einstellungsseite lässt sich unter "Genauigkeit der
Geschwindigkeitsmessung" eine von drei Stufen wählen
(`models/speed_accuracy_mode.dart`, `SpeedAccuracyMode`):

| Stufe | GPS-Genauigkeit | Mindestabstand für Updates | Effekt |
|---|---|---|---|
| Akkusparend | `LocationAccuracy.medium` | 15 m | schont den Akku, seltenere/ungenauere Anzeige |
| Ausgewogen (Standard) | `LocationAccuracy.high` | 1 m | guter Kompromiss |
| Maximale Genauigkeit | `LocationAccuracy.best` | 0 m | schnellstmögliche, genaueste Anzeige, höherer Akkuverbrauch |

Direkt über der Auswahl steht ein dauerhaft sichtbarer Hinweis (mit
Akku-Symbol, hervorgehobener Hintergrund), dass eine höhere Genauigkeit/
Aktualität den Akkuverbrauch spürbar erhöhen kann - wie gefordert.

Eine Änderung wirkt sich beim nächsten Öffnen der Tacho-Seite aus (jede
Seite bekommt beim Öffnen einen frischen `SpeedService`, siehe
`HomeShell`/Abschnitt 16 - ein bewusst einfacher, robuster Mechanismus
statt eines mitten im laufenden Stream nötigen Neustarts der
GPS-Abfrage).

## 5. Persistierte Einstellungen (bleiben nach App-Neustart erhalten)

Folgende vier Einstellungen werden über `services/app_preferences.dart`
(Paket `shared_preferences`) dauerhaft auf dem Gerät gespeichert und beim
nächsten App-Start automatisch wiederhergestellt:

- Anzeigeeinheit auf der Tacho-Seite (m/s / km/h / kn)
- Kartendarstellung auf Track-Seite und Track-Detailansicht gemeinsam
  (Landkarte / Seekarte, siehe Abschnitt 9)
- Anzeigemodus auf der Einstellungen-Seite (System / Hell / Dunkel)
- Genauigkeit der Geschwindigkeitsmessung auf der Einstellungen-Seite

**Bewusst NICHT** persistiert werden die aktuelle Kartenausrichtung/
-position sowie die Nordausrichtungs-Sperre (siehe Abschnitt 9) von
Track-Seite und Track-Detailansicht - beide starten bei jedem Aufruf
wieder in ihrem jeweils sinnvollen Ausgangszustand (aktuelle Position bzw.
passend eingerahmter Streckenverlauf, Drehsperre stets zunächst
deaktiviert), das ist eine kurzfristige Bedienhilfe, kein dauerhaftes
Einstellungsmerkmal.

## 6. Stillstandserkennung über den Beschleunigungssensor

GPS-Positionen "wandern" durch Messungenauigkeiten leicht, auch wenn sich
das Gerät gar nicht bewegt (z. B. auf einem Tisch liegend) - daraus
errechnet sich dann eine kleine, aber ungleich Null schwankende
Geschwindigkeit, obwohl eigentlich 0 angezeigt werden sollte.

`services/motion_service.dart` nutzt dafür ein zweites, von GPS
unabhängiges Signal: den Beschleunigungssensor (`sensors_plus`,
`userAccelerometerEventStream` - Beschleunigung OHNE Erdanziehung). Liegt
das Gerät wirklich still, misst dieser nahezu exakt Null; jede
tatsächliche Bewegung erzeugt einen messbaren Ausschlag.

**Hysterese statt einem einzelnen Schwellenwert:** Eine frühere Version
verglich den gemittelten Beschleunigungswert mit nur einem einzigen
Schwellenwert - lag der Durchschnitt genau in dessen Nähe, kippte die
Erkennung in der Praxis sehr häufig hin und her, was die
Geschwindigkeitsanzeige spürbar "flackern" ließ. `motion_service.dart`
verwendet daher zwei Schwellenwerte (0,10 m/s² zum Eintreten in den
Ruhezustand, 0,22 m/s² zum Verlassen) mit einer "toten Zone" dazwischen,
plus eine kurze Entprellung (ein Zustandswechsel muss sich über mehrere
aufeinanderfolgende Messungen bestätigen, bevor er übernommen wird). Ein
einmal erkannter Zustand bleibt dadurch deutlich stabiler.

**Kombinationslogik** (`speed_page.dart`): Die Anzeige wird NUR dann auf 0
korrigiert, wenn ZWEI Bedingungen gleichzeitig zutreffen: (1) der
Beschleunigungssensor meldet Stillstand UND (2) der GPS-Rohwert selbst ist
bereits klein (< 8 km/h). Diese Kombination ist wichtig: Ein Fahrzeug, das
sehr ruhig und gleichmäßig mit z. B. 60 km/h fährt, könnte theoretisch
ebenfalls kaum Beschleunigung zeigen - würde aber wegen der hohen
GPS-Geschwindigkeit trotzdem NICHT auf 0 gesetzt. Unter der Anzeige steht
dauerhaft eine kleine Hinweiszeile: Ist die Korrektur aktiv, erscheint dort
"Stillstand erkannt - Anzeige auf 0 korrigiert", andernfalls ein einfacher
Platzhalter ("-") - die Zeile bewusst IMMER sichtbar zu halten (statt sie
nur bei aktiver Korrektur ein-/auszublenden) vermeidet ein zusätzliches,
vom eigentlichen Geschwindigkeitswert unabhängiges Flackern des Layouts.

Auf Geräten ohne Beschleunigungssensor (selten) verhält sich die App
einfach wie zuvor - ausschließlich auf Basis der GPS-Rohdaten.

## 7. Bildschirm-Wachhalten (Wakelock)

Sowohl auf der Tacho- als auch auf der Kompass-Seite bleibt der
Bildschirm an, solange die jeweilige Seite sichtbar ist (Paket
`wakelock_plus`) - typischer Anwendungsfall: Gerät liegt sichtbar während
der Fahrt, die Anzeige soll nicht durch die automatische
Bildschirmsperre verdeckt werden. Beim Verlassen der jeweiligen Seite
wird das Wachhalten automatisch wieder aufgehoben. Die Track-Seite hält
den Bildschirm ebenfalls wach, aber NUR während tatsächlich AKTIV
aufgezeichnet wird (nicht bei einer Pause und nicht in der reinen
Detailansicht eines bereits gespeicherten Tracks, siehe Abschnitt 19) - die
Einstellungsseite hält den Bildschirm bewusst NICHT wach.

## 8. Offline-Kartennutzung - was umgesetzt ist und was bewusst nicht

**Umgesetzt:** `flutter_map` bringt seit Version 8.2.0 ein eingebautes
Kachel-Caching mit; `ui/widgets/map_tile_layers.dart` setzt es explizit
ein (`NetworkTileProvider(cachingProvider: BuiltInMapCachingProvider...)`,
Cache-Obergrenze 300 MB, sowohl für die Landkarte als auch für das
Seemarken-Overlay) - dieser Baustein wird von Track-Seite und
Track-Detailansicht gleichermaßen verwendet (siehe Abschnitt 9).
Bereits online angezeigte Kartenausschnitte bleiben dadurch auch ohne
Internetverbindung sichtbar - ganz automatisch, einfach durch normales
Ansehen der Karte.

**Bewusst NICHT umgesetzt:** ein Button zum vorausschauenden
Herunterladen ganzer, noch nie angezeigter Regionen (z. B. "gesamtes
Fahrgebiet vor der Tour herunterladen"). Dagegen sprechen zwei konkrete
Gründe:

1. **Nutzungsbedingungen von OpenStreetMap:** Der offizielle Tile-Server,
   den diese App verwendet, verbietet ausdrücklich automatisiertes
   Massen-Herunterladen von Kacheln ("bulk downloading") ohne vorherige
   Absprache - das würde bei konsequenter Nutzung riskieren, dass die App
   irgendwann serverseitig blockiert wird.
2. **Lizenzfrage beim naheliegenden Paket:** Das einzige ausgereifte
   Flutter-Paket für genau diesen Zweck (`flutter_map_tile_caching`,
   "FMTC") steht unter der GPL-Lizenz - eine Einbindung würde
   voraussichtlich bedeuten, dass auch diese App unter einer damit
   kompatiblen, quelloffenen Lizenz weitergegeben werden müsste (bzw.
   eine kostenpflichtige Lizenz vom Autor nötig wäre). Das ist eine
   Entscheidung, die dir und nicht mir zustehen sollte - ich wollte sie
   dir nicht stillschweigend "unterjubeln".

**Falls du das trotzdem willst:** Der sauberste Weg wäre ein
kommerzieller Kartenanbieter mit eigenem Offline-SDK und ausdrücklich
erlaubtem Bulk-Download (z. B. Mapbox, Stadia Maps, Thunderforest) - das
würde allerdings einen eigenen (meist kostenpflichtigen) API-Key
erfordern, im Unterschied zum bisherigen Ansatz dieses Projekts, komplett
ohne Registrierung auszukommen. Sag Bescheid, falls du diesen Weg gehen
möchtest, dann bauen wir das gezielt darauf auf.

## 9. Kartendarstellung: gemeinsame Bausteine statt eigener Kartenseite

**Änderung gegenüber einer früheren Version:** Es gab ursprünglich eine
eigenständige "Karte"-Seite, die ausschließlich die aktuelle Live-Position
ohne weiteren Kontext zeigte (reine "Wo bin ich"-Ansicht). Diese Funktion
ist inzwischen bereits Teil der Track-Aufzeichnung (siehe Abschnitt 19) -
eine separate Seite dafür wäre redundant gewesen und wurde daher entfernt.
Die Kartendarstellung selbst (Kacheln, Caching, Landkarte/Seekarte-
Umschaltung, Nordausrichtungs-Fixierung) lebt stattdessen als gemeinsam
genutzter Baustein in `ui/widgets/map_tile_layers.dart` (Kachel-Ebenen
inkl. Attribution), `ui/widgets/nautical_mode_button.dart` (Umschalt-
Button) und `ui/widgets/north_lock_button.dart` (Nordausrichtungs-Button)
fort und wird von zwei Stellen verwendet:

- **`track_page.dart`** (Track-Aufzeichnung, Abschnitt 19): zeigt die
  Live-Karte während der Aufzeichnung.
- **`track_detail_page.dart`** (Detailansicht eines gespeicherten Tracks,
  ebenfalls Abschnitt 19): zeigt den vollständigen, bereits
  aufgezeichneten Streckenverlauf.

**Landkarte/Seekarte-Umschaltung** (Button, `NauticalModeButton`): schaltet
zusätzlich zur normalen OpenStreetMap-Landkarte ein transparentes
Seemarken-Overlay von OpenSeaMap ein (Bojen, Leuchttürme,
Fahrwasser-Markierungen etc., `tiles.openseamap.org/seamark/...` -
ebenfalls kostenlos, kein API-Key). **Wichtige Einschränkung:** Das ist
KEINE amtliche Seekarte mit Tiefenangaben/Isobathen - solche Daten sind
i. d. R. kostenpflichtig/lizenzpflichtig und in keiner kostenlosen,
API-Key-freien Quelle verfügbar. Die Umsetzung folgt damit genau dem, was
OpenSeaMap selbst als "nautische Ansicht" anbietet (Basiskarte +
Seemarken-Overlay). Die Wahl wird über `AppPreferences` persistiert
(`mapNauticalMode`, siehe Abschnitt 5) und gilt daher geräteweit für beide
Kartenansichten gemeinsam, nicht getrennt je Seite.

**Nordausrichtung einrasten** (Button, `NorthLockButton`): Ein Antippen
richtet die Karte einmalig nach Norden aus (Drehung auf 0°) UND rastet
diese Ausrichtung anschließend ein - die Dreh-Geste (Zwei-Finger-Rotation)
wird dabei gezielt deaktiviert (`InteractiveFlag.all & ~InteractiveFlag.
rotate`), alle anderen Gesten (Verschieben, Zoomen) bleiben uneingeschränkt
nutzbar. Ein kleines Schloss-Symbol am Button zeigt den eingerasteten
Zustand an; erneutes Antippen gibt die Drehung wieder frei. Anders als die
Landkarte/Seekarte-Wahl wird dieser Zustand bewusst NICHT persistiert
(siehe Abschnitt 5) - jede Seite startet bei jedem Aufruf wieder frei
drehbar. Dieser Button war Teil der frühen, inzwischen entfallenen
eigenständigen Kartenseite und ist auf Wunsch wieder Teil beider
Kartenansichten (Track-Aufzeichnung und Track-Detailansicht).

## 10. Kompass: dekorative Darstellung & Kursangabe ausschließlich 0°-360°

Die Kompassrose (`ui/widgets/compass_dial.dart`) wurde gegenüber der
ursprünglich schlichten Version (nur vier beschriftete Striche) deutlich
aufgewertet:

- Zifferblatt mit dezentem Verlauf und weichem Schlagschatten für
  Tiefenwirkung
- Mehrteiliger, dekorativer Rahmen ("Bezel") mit Glanzverlauf
- Klassisches 8-zackiges Sternmuster einer Kompassrose im Hintergrund
- Feine Grad-Skala mit Haupt- (alle 45°), Zwischen- (alle 15°) und
  Feinteilstrichen (alle 5°) statt nur vier grober Striche
- Acht beschriftete Himmelsrichtungen (N, NO, O, SO, S, SW, W, NW),
  Norden farblich hervorgehoben (Rot, passend zum App-Icon)
- Dezenter Glanzstreifen ("Glaseffekt") über dem oberen Bereich
- Feststehender roter "Steuerstrich" oben, der die tatsächliche
  Geräteausrichtung anzeigt (Funktionsprinzip eines klassischen
  Schiffskompasses)

**Kursangabe ausschließlich 0°-360°, nie negativ:**
`services/compass_service.dart` normalisiert jeden vom Sensor gelieferten
Winkel explizit auf den Bereich [0, 360). Laut Dokumentation von
`flutter_compass` sollte `heading` zwar bereits ausschließlich Werte in
diesem Bereich liefern, in der Praxis wurden auf manchen Geräten aber
vereinzelt knapp negative Werte beobachtet (z. B. -0,4° statt 359,6°,
typisches Sensorrauschen nahe der 0°/360°-Grenze) - die Normalisierung
schließt das unabhängig vom konkreten Gerät zuverlässig aus.

**Höhenanzeige:** Unterhalb der Peilungsgenauigkeit zeigt die
Kompass-Seite zusätzlich die aktuelle Höhe inkl. Genauigkeit und Quelle
an. Zwei kombinierte Quellen:

- **GPS** (`services/altitude_service.dart`, `Position.altitude`/
  `altitudeAccuracy`) - liefert die absolute, aber eher grobe Höhe
  (Abweichungen von 10-30 m sind selbst bei gutem Empfang keine
  Seltenheit, da die Satellitengeometrie für die Höhenbestimmung
  ungünstiger ist als für die waagerechte Position).
- **Barometer** (`services/barometer_altitude_service.dart`, Luftdruck
  über `sensors_plus`) - sofern das Gerät einen Drucksensor besitzt,
  liefert er deutlich feinere, praktisch rauschfreie relative
  Höhenänderungen (Auflösung im Dezimeterbereich). Ein Barometer kennt
  aber nur den Luftdruck, keine absolute Höhe - deshalb wird er
  fortlaufend gegen die jeweils aktuellste GPS-Höhe kalibriert
  (internationale barometrische Höhenformel für die Differenz zum
  Kalibrierpunkt). Das ist eine einfache, praktische Sensor-Fusion (kein
  vollwertiges Kalman-Filter), aber ein guter Kompromiss zwischen Aufwand
  und Nutzen.

Sobald ein Barometer verfügbar ist, übernimmt die Anzeige automatisch
dessen präzisere Werte (z. B. "Höhe: 512,3 m (± 0,3 m, Barometer)"),
andernfalls bleibt es bei der GPS-Höhe (z. B.
"Höhe: 512 m (± 8 m, GPS)"). Weitere Design-Entscheidungen:
- Ein eigener, schlanker Standort-Stream statt Wiederverwendung des
  Tacho-`SpeedService` - die Höhe muss nicht so oft aktualisiert werden
  wie die Geschwindigkeit, und beide Seiten sollen unabhängig
  voneinander funktionieren.
- Fehlt die Standort-Berechtigung, wird (anders als auf der Tacho-Seite)
  KEIN blockierender Hinweisbildschirm angezeigt - der Kompass selbst
  benötigt keinen Standortzugriff, die Höhe erscheint in diesem Fall
  einfach als "nicht verfügbar" (auch das Barometer bleibt dann
  unkalibriert, da ihm die GPS-Referenz fehlt).
- Zusätzliche Android-Berechtigungen sind für beides nicht nötig - für
  GPS werden dieselben Standort-Berechtigungen genutzt wie für Tacho und
  Karte (siehe Abschnitt 2), der Barometer-Zugriff benötigt unter
  Android keine gesonderte Laufzeit-Berechtigung.


## 11. Tacho-Seite: Sieben-Segment-Anzeige & Einheiten-Auswahl

- **Rote Sieben-Segment-Anzeige** (`ui/widgets/seven_segment_display.dart`):
  Die Geschwindigkeit wird als klassische, komplett selbst gezeichnete
  (kein Font-Asset, keine Lizenzfragen) rote Sieben-Segment-Anzeige
  dargestellt, inkl. sehr stark abgeschwächter "Geister"-Segmente
  (unbeleuchtete Segmente, Alpha 0,015 - nur noch ein ganz leichter
  Hauch sichtbar) wie bei echten Digitalanzeigen. Unterstützt Ziffern 0-9
  und ein Komma als Dezimaltrennzeichen. Die Einheit steht unterhalb
  statt neben der Zahl, damit die Anzeige selbst die volle verfügbare
  Breite nutzen kann.
- **Einheiten-Auswahl**: `SegmentedButton` mit Icons Person (m/s, zu Fuß),
  Auto (km/h), Segelboot (kn) - im selben Stil wie die
  Anzeigemodus-Auswahl in den Einstellungen. Beide `SegmentedButton`s
  (Tacho-Seite UND Einstellungsseite) sind bewusst über
  `SizedBox(width: double.infinity)` auf volle Breite gestreckt UND
  beide Seiten verwenden dasselbe horizontale Padding (16) - dadurch
  sind beide Steuerelemente exakt gleich breit, und jedes Segment
  bekommt maximal möglichen Platz, damit die Beschriftung sicher
  einzeilig bleibt.

## 12. Info-Seite & obere App-Leiste

Alle vier Hauptseiten teilen sich eine gemeinsame `AppBar` in
`HomeShell` (Seitentitel links, Info-Button rechts). Das erfüllt zwei
Zwecke gleichzeitig:

- **Oberer Systembereich bleibt frei:** `Scaffold` + `AppBar`
  reservieren automatisch den Bereich für Uhrzeit/Akkustand/Empfang -
  App-Inhalte werden dort nie hineingezeichnet, auf allen vier Seiten
  gleichermaßen.
- **Info-Button auf jeder Seite:** Ein Antippen des Info-Icons (oben
  rechts, auf allen vier Hauptseiten identisch erreichbar) öffnet die
  neue `ui/info_page.dart` mit:
  - Name und Version der App - über `package_info_plus` zur Laufzeit
    direkt aus dem tatsächlichen Build ausgelesen (nicht fest im Code
    hinterlegt), bleibt dadurch auch nach künftigen
    Versionserhöhungen in `pubspec.yaml` automatisch korrekt.
  - Name des Programmautors (Claus J. Bauer).
  - Ein Button "Verwendete Module", der Flutters eingebaute
    Lizenzseite öffnet (`showLicensePage(...)`) - listet automatisch
    alle in der App verwendeten Pakete samt Lizenztexten auf, ohne
    dass diese Liste manuell gepflegt werden müsste.

## 13. Automatische Silbentrennung im gesamten Projekt

Alle Fließtext-Ausgaben nutzen `AutoHyphenatingText` (Paket
`auto_hyphenating_text`) statt des Standard-`Text`-Widgets - ein direkter
Ersatz mit identischer Konstruktor-Signatur. Initialisiert wird die
deutsche Trennung (Reform 1996) einmalig beim App-Start in `main.dart`
(`initHyphenation(DefaultResourceLoaderLanguage.de1996)`). Zwei bewusste
Ausnahmen:
- Die Himmelsrichtungs-Buchstaben (N/O/S/W) im Kompass werden direkt auf
  die Canvas gezeichnet (`TextPainter`/`TextSpan`), nicht über ein
  Text-Widget - dort greift `AutoHyphenatingText` technisch nicht (und
  wäre bei Einzelbuchstaben ohnehin wirkungslos).
- Die Beschriftungen der unteren Navigationsleiste (`home_shell.dart`)
  sind bei `NavigationDestination` als reiner `String`, nicht als
  Widget, vorgegeben - Flutter erlaubt dort keinen Ersatz durch ein
  Text-Widget.
- Die Labels innerhalb der `ButtonSegment`s beider `SegmentedButton`s
  (Einheiten-Auswahl in `speed_page.dart`, Anzeigemodus-Auswahl in
  `settings_page.dart`) verwenden ebenfalls bewusst normales `Text`
  statt `AutoHyphenatingText`: `SegmentedButton` berechnet für die
  gleichmäßige Aufteilung der Segmente die intrinsische Breite seiner
  Labels, `AutoHyphenatingText` nutzt dafür intern aber einen
  `LayoutBuilder`, der laut Flutter-Dokumentation keine intrinsischen
  Berechnungen unterstützt ("LayoutBuilder does not support returning
  intrinsic dimensions") - eine Kombination beider führt zu einem
  Laufzeitfehler beim Öffnen der jeweiligen Seite. Bei den hier stets
  kurzen Wörtern (m/s, km/h, kn, System, Hell, Dunkel) wäre eine
  Silbentrennung ohnehin nie nötig gewesen.

## 13a. Locale-Initialisierung für Datumsformatierung (`DateFormat`)

Ähnlich wie die Silbentrennung (Abschnitt 13) benötigt auch die deutsche
Datumsformatierung eine einmalige Initialisierung beim App-Start - in
`main.dart` per `await initializeDateFormatting('de_DE')` (Paket `intl`,
Unterpaket `date_symbol_data_local.dart`).

**WICHTIG, da leicht zu übersehen:** Das gilt NUR für `DateFormat`, NICHT
für `NumberFormat` - beide kommen zwar aus demselben Paket `intl` und
werden beide mit `'de_DE'` als Locale verwendet (`NumberFormat` bereits an
mehreren Stellen im Projekt, z. B. `util/speed_formatter.dart` und die
Grad-/Höhenanzeige in `compass_page.dart`), verhalten sich hierbei aber
unterschiedlich: `NumberFormat` bringt seine Symboldaten für gängige
Locales bereits fertig mit, `DateFormat` dagegen lädt seine (deutlich
umfangreicheren) Locale-Daten bewusst NICHT automatisch, um Apps, die sie
nicht brauchen, nicht unnötig aufzublähen - ohne den obigen Aufruf wirft
jede Verwendung von `DateFormat` mit einer nicht-englischen Locale zur
Laufzeit eine `LocaleDataException`.

Erstmals verwendet wird `DateFormat` in `util/track_formatter.dart`
(Datums-/Uhrzeitanzeige eines Tracks, siehe Abschnitt 19) - ohne die
Initialisierung in `main.dart` wäre dort z. B. der
"Aufzeichnung beenden"-Dialog auf der Track-Seite wirkungslos gewesen: Er
ruft als Erstes `TrackFormatter.suggestName()` (intern ein `DateFormat`)
auf, und eine dabei geworfene Exception verpufft innerhalb eines
Button-Callbacks unsichtbar, ohne Absturz oder erkennbare Fehlermeldung -
von außen sah das schlicht wie ein wirkungsloser Button aus.

## 14. App-Icon

Im Ordner `assets/icon/` liegen drei bereits fertig erzeugte Bilddateien
bei - ein deutlich dekorativeres Motiv (angelehnt an die Kompass-Seite in
der App: Bezel-Ring, Sternrose, Grad-Skala, glänzendes Zifferblatt), das
mehrere Funktionen der App zugleich aufgreift:

- Radialer Farbverlauf im Hintergrund (helleres Teal oben links als
  "Lichtquelle", dunkler werdend zum Rand) statt einer flachen Fläche -
  sorgt für spürbar mehr Tiefe/Plastizität.
- Ein großzügig dimensionierter Ring mit Bezel, halbtransparentem
  Zifferblatt, dezentem Sternrosen-Muster, Grad-Teilstrichen und
  Glanzlicht - wirkt zugleich wie ein Kompass mit Haupt-Himmelsrichtungen
  UND wie eine Tacho-Skala.
- Eine klassische zweifarbige Kompassnadel (rote Spitze = Norden, weiße
  Spitze = Süden) mit glänzender Nabe - repräsentiert die Kompass-Funktion.
- Ein Karten-Pin-Symbol in Akzentfarbe (Amber/Gelb) mit eigenem
  Schlagschatten am Rand des Rings - repräsentiert die Karten-Funktion.

Die Einstellungsseite ist bewusst NICHT im Icon dargestellt - ein
Zahnrad-Symbol zusätzlich zu den genannten Elementen hätte das Icon bei
den kleinen, auf dem Startbildschirm tatsächlich sichtbaren Größen eher
überladen als verbessert; das ist bei App-Icons allgemein üblich.

Farblich passt das Motiv weiterhin zum App-Theme (`colorSchemeSeed:
Colors.teal`):

- `icon.png` (1024×1024, deckend, Verlaufshintergrund + Motiv): Vollbild-Icon.
- `icon_background.png` (1024×1024, deckend, NUR der Verlauf ohne Motiv):
  Hintergrund-Ebene für Android-"Adaptive Icons" (Android 8+) - dadurch
  bleibt der Farbverlauf auch dort erhalten, statt auf eine einfarbige
  Fläche zurückzufallen.
- `icon_foreground.png` (1024×1024, transparent, NUR das Motiv, mittig
  verkleinert): Vordergrund-Ebene für Adaptive Icons - der Launcher legt
  je nach Gerät/Hersteller eine eigene Form (Kreis, Squircle, ...)
  darüber; das Motiv bleibt dafür bewusst innerhalb einer sicheren,
  mittigen Zone.

Erzeugung erfolgt über das Paket `flutter_launcher_icons` (bereits in
`pubspec.yaml` als Dev-Abhängigkeit samt Konfiguration hinterlegt, ohne
iOS-Teil). Nach `flutter pub get` einmalig ausführen:

```bash
dart run flutter_launcher_icons
```

Das schreibt automatisch alle benötigten Icon-Größen direkt in den
`android/`-Projektordner (u. a. `mipmap-*`-Verzeichnisse). Der Befehl kann
jederzeit erneut ausgeführt werden, falls sich das Motiv später ändert -
dazu einfach die drei Dateien in `assets/icon/` ersetzen (gleiche
Bildgröße 1024×1024 beibehalten) und den Befehl erneut aufrufen.

**Hinweis:** Das Icon-Motiv wurde programmatisch erzeugt (kein
existierendes Logo, keine fremden Bildrechte) und kann bei Bedarf leicht
angepasst werden (Farben, Anordnung etc.) - melde dich einfach, falls du
eine andere Variante möchtest.

**Aktualisierung (Track-Symbolik):** Das ursprüngliche Motiv zeigte
einen einzelnen Karten-Pin unten rechts sowie darunter zwei blaue
Wellenlinien (Andeutung von Wasser/Seekarte). Mit Blick auf die geplante
Track-Aufzeichnung/-speicherung wurde das Icon angepasst: Statt des
einen Pins gibt es jetzt zwei kleinere, diagonal zueinander versetzte
Pins unten links, verbunden durch eine rote, leicht S-förmig geschwungene
gestrichelte Linie - ein gängiges Symbol für einen aufgezeichneten Track
zwischen zwei Punkten. Die ursprünglichen blauen Wellenlinien unten
rechts wurden dabei bewusst unverändert beibehalten (unabhängig von der
Track-Darstellung) - sie stehen weiterhin für die Seekarten-Option der
Kartendarstellung (siehe Abschnitt 9) und sind von der Track-Symbolik
inhaltlich unabhängig.

## 15. Wichtige fachliche Annahmen, die im Code kommentiert sind

- **Nachkommastellen-Regel** (`util/speed_formatter.dart`): "Unterhalb
  von 10 km/h eine Nachkommastelle, sonst keine" wird ausdrücklich anhand
  des km/h-Werts entschieden - unabhängig davon, ob gerade m/s, km/h oder
  kn angezeigt wird.
- **Satellitenanzahl nur unter Android** (siehe Abschnitt 3) - ohnehin
  passend, da die App ausschließlich für Android gebaut wird.
- **Stillstands-Schwelle 8 km/h** (siehe Abschnitt 6) sowie die
  **Hysterese-Schwellenwerte 0,10/0,22 m/s²** (`motion_service.dart`) sind
  sinnvoll gewählte, aber letztlich empirische Annahmen - je nach
  Gerät/Sensor-Qualität ggf. nachjustierbar.
- **Genauigkeitsstufe wirkt erst beim nächsten Seitenaufruf** (siehe
  Abschnitt 4) - bewusste Design-Entscheidung zugunsten von Einfachheit/
  Robustheit gegenüber einem Neustart des laufenden GPS-Streams mitten in
  der Nutzung.
- **Offline-Kartenkacheln** decken nur bereits angezeigte Ausschnitte ab,
  kein Vorab-Download ganzer Regionen (siehe Abschnitt 8 für die
  ausführliche Begründung).
- **"Seekarte"** meint das OpenSeaMap-Seemarken-Overlay, keine amtliche
  Tiefenkarte (siehe Abschnitt 9).

## 16. Architekturüberblick

```
lib/
  models/
    speed_unit.dart          Enum m/s | km/h | kn inkl. Umrechnung
    speed_accuracy_mode.dart Enum Akkusparend | Ausgewogen | Maximal
    speed_reading.dart       Datenmodell einer Geschwindigkeitsmessung
    compass_reading.dart     Datenmodell einer Kompassmessung
    altitude_reading.dart    Datenmodell einer Höhenmessung
    track_point.dart         Datenmodell eines einzelnen Track-GPS-Punkts (Abschnitt 19)
    recorded_track.dart      Datenmodell eines abgeschlossenen, gespeicherten Tracks (Abschnitt 19)
  services/
    speed_service.dart      GPS-Geschwindigkeit (Genauigkeitsstufe siehe Abschnitt 4)
    motion_service.dart     Stillstandserkennung über Beschleunigungssensor (Abschnitt 6)
    satellite_service.dart  Satellitenanzahl (nur Android, siehe Abschnitt 3)
    compass_service.dart    Kompass-Peilung
    altitude_service.dart   Höhe per GPS, für die Kompass-Seite (Abschnitt 10)
    barometer_altitude_service.dart  Präzisere Höhe per Barometer, kalibriert
                                      gegen GPS (Abschnitt 10)
    app_preferences.dart    Anzeigemodus + Einheit + Genauigkeitsstufe +
                             Kartendarstellung, persistiert (Abschnitt 5)
    track_recording_service.dart  Start/Pause/Fortsetzen/Beenden einer
                                    Track-Aufzeichnung (Abschnitt 19 - lebt
                                    bewusst länger als eine Seite, siehe dort)
    track_storage_service.dart    Speichern/Laden/Löschen aufgezeichneter
                                    Tracks als JSON-Dateien (Abschnitt 19)
    track_import_export_service.dart  GPX-Import/-Export (Datei-Ein-/
                                        Ausgabe, siehe Abschnitt 20)
  ui/
    home_shell.dart        Obere App-Leiste + Navigationsleiste + Seitenwechsel
    speed_page.dart        Tacho-Seite (Hauptseite, Start-Tab)
    compass_page.dart      Kompassseite
    track_page.dart        Track-Seite (Aufzeichnung + gespeicherte Tracks, Abschnitt 19)
    track_detail_page.dart Detailansicht eines gespeicherten Tracks (Abschnitt 9/19)
    settings_page.dart     Einstellungsseite
    info_page.dart         Info-Seite (Abschnitt 12)
    widgets/compass_dial.dart          Kompassrose (CustomPainter)
    widgets/seven_segment_display.dart Sieben-Segment-Anzeige (CustomPainter)
    widgets/map_tile_layers.dart       Gemeinsame Kartenkacheln + Attribution (Abschnitt 9)
    widgets/nautical_mode_button.dart  Gemeinsamer Landkarte/Seekarte-Button (Abschnitt 9)
    widgets/north_lock_button.dart     Gemeinsamer Nordausrichtungs-Button (Abschnitt 9)
  util/
    speed_formatter.dart   Formatierung inkl. Nachkommastellen-Regel
    track_formatter.dart   Formatierung von Distanz/Dauer/Datum eines Tracks (Abschnitt 19)
    gpx_converter.dart     Reine GPX ⇄ RecordedTrack-Umwandlung (Abschnitt 20)
  main.dart
native_android/
  de/clausjbauer/ontour/MainActivity.kt   Siehe Abschnitt 3
assets/icon/
  icon.png             App-Icon, vollflächig (siehe Abschnitt 14)
  icon_background.png  App-Icon, Verlaufshintergrund für Android Adaptive Icons
  icon_foreground.png  App-Icon, Vordergrund für Android Adaptive Icons
```

Zur Reihenfolge: Die Navigationsleiste listet die Seiten als Tacho /
Kompass / Track / Einstellungen, und die App startet mit der Tacho-Seite
als aktivem Tab (`_selectedIndex = 0` in `HomeShell`) - passend dazu, dass
die Geschwindigkeitsanzeige die Hauptfunktion der App ist.

Zum Seitenwechsel: `HomeShell` hält die jeweils sichtbare Seite bewusst
NICHT über einen `IndexedStack` im Hintergrund am Leben, sondern disposed
sie beim Tab-Wechsel und erzeugt sie bei erneutem Aufruf neu. Dadurch
werden GPS-/Kompass-/Bewegungssensoren zuverlässig gestoppt, sobald die
jeweilige Seite nicht sichtbar ist - das spart spürbar Akku UND sorgt
dafür, dass eine geänderte Genauigkeitsstufe (Abschnitt 4) beim nächsten
Aufruf der Tacho-Seite automatisch greift.

**Ausnahme:** Der `TrackRecordingService` (siehe Abschnitt 19) wird davon
bewusst ausgenommen - er wird nicht in `TrackPage`, sondern einmalig in
`HomeShell` selbst erzeugt und nur an `TrackPage` durchgereicht, damit eine
laufende Track-Aufzeichnung beim Wechsel auf einen anderen Tab nicht
abbricht.

## 17. Nächste sinnvolle Ausbaustufe (nicht Teil dieser Umsetzung)

- Vorausschauendes Herunterladen ganzer Kartenregionen für die komplett
  netzunabhängige Nutzung, z. B. auf Basis eines kommerziellen
  Kartenanbieters mit eigenem, ausdrücklich für Bulk-Download
  freigegebenem SDK (siehe Abschnitt 8 für die Begründung, warum das
  aktuell bewusst nicht Teil der Umsetzung ist).

## 18. Hinweis zur Umbenennung Andrivol -> onTour

Diese Version des Projekts wurde von "Andrivol" in "onTour" umbenannt.
Betroffen waren:

- **App-Anzeigename**: `MaterialApp(title: ...)` in `main.dart` sowie der
  Fallback-Name auf der Info-Seite (`ui/info_page.dart`), falls
  `package_info_plus` noch keine Daten geliefert hat.
- **App-Klasse**: `AndrivolApp` in `main.dart` heißt jetzt `OnTourApp`.
- **`pubspec.yaml`**: `name: ontour` (Paketname, klein geschrieben - Dart-
  Paketnamen dürfen keine Großbuchstaben enthalten).
- **Android-`applicationId`**: `de.clausjbauer.ontour` statt
  `de.clausjbauer.andrivol` (siehe `--project-name ontour` im
  `flutter create`-Befehl in Abschnitt 1 sowie den User-Agent für die
  Kartenkacheln in `widgets/map_tile_layers.dart`).
- **Nativer Event-Channel**: `ontour/gnss_satellite_count` statt
  `andrivol/gnss_satellite_count` in `services/satellite_service.dart`.

**WICHTIG - was du selbst noch anpassen musst:** Die native
`MainActivity.kt` (Abschnitt 3) war kein Bestandteil des mir
vorliegenden Quelltexts und konnte daher hier nicht automatisch
angepasst werden. Falls du sie bereits verwendest, musst du dort von
Hand:

1. den registrierten Event-Channel-Namen im Kotlin-Code von
   `"andrivol/gnss_satellite_count"` auf
   `"ontour/gnss_satellite_count"` ändern (muss exakt mit dem oben
   genannten Dart-seitigen Namen übereinstimmen), und
2. die `package`-Zeile sowie den Dateipfad von
   `de/clausjbauer/andrivol/MainActivity.kt` nach
   `de/clausjbauer/ontour/MainActivity.kt` verschieben/umbenennen.

Falls du bereits ein bestehendes Flutter-Projekt (mit `android/`-Ordner)
hast statt es neu über `flutter create` anzulegen, muss zusätzlich die
`applicationId` in `android/app/build.gradle` (bzw. `build.gradle.kts`)
manuell von `de.clausjbauer.andrivol` auf `de.clausjbauer.ontour`
geändert werden - ein reiner Dateiname-/Code-Austausch in `lib/` genügt
dafür nicht.

## 19. Track-Seite: Aufzeichnung, Speicherung und Detailansicht

Die dritte Seite "Track" (zwischen Kompass und Einstellungen) erlaubt das
Aufzeichnen einer GPS-Strecke sowie das spätere Anzeigen und Löschen
bereits gespeicherter Tracks über eine eigene Detailseite.

**Zur Begrifflichkeit:** Diese Funktion hieß in einer früheren Version
"Route" (Seite, Modelle, Services, Anzeigetexte) und wurde durchgängig in
"Track" umbenannt - Dateien, Klassen und Variablen entsprechend.

**Aufzeichnung (`services/track_recording_service.dart`):**
- Eigener, von Tacho/Höhe unabhängiger GPS-Stream (`LocationAccuracy.best`,
  `distanceFilter: 3` - kleiner als früher bei der eigenständigen
  Kartenseite, da für eine genaue Streckenlinie auch kleine Bewegungen
  erfasst werden sollen; Genauigkeit hat hier bewusst Vorrang vor
  Akkuverbrauch).
- Drei Zustände: `idle` (nichts aufgezeichnet) → `recording` (GPS-Punkte
  werden gesammelt) ⇄ `paused` (z. B. für eine Rast unterwegs - gesammelte
  Punkte bleiben erhalten, es kommen nur keine neuen hinzu, und die
  angezeigte Dauer läuft nicht weiter).
- Streckenlänge wird laufend aus den Abständen aufeinanderfolgender Punkte
  aufsummiert (`Geolocator.distanceBetween`), nicht erst beim Beenden neu
  berechnet.
- Die tatsächliche Aufzeichnungsdauer (`elapsed`) rechnet Pausenzeiten
  automatisch heraus.
- Beim Beenden (`stop`) wird wahlweise gespeichert (mit frei wählbarem
  Namen, vorbelegt mit "Track vom TT.MM.JJJJ, HH:MM") oder verworfen
  (`discard`). Ein Track mit weniger als zwei Punkten ergibt keinen
  gültigen `RecordedTrack` (z. B. bei versehentlichem Start).

**WICHTIGE Architektur-Ausnahme:** Anders als alle übrigen Services dieses
Projekts wird der `TrackRecordingService` NICHT frisch pro Seitenaufruf
erzeugt, sondern einmalig in `HomeShell` gehalten und nur an `TrackPage`
durchgereicht (siehe Abschnitt 16). Grund: Eine laufende Aufzeichnung muss
weiterlaufen, auch wenn währenddessen z. B. kurz die Kompass-Seite
betrachtet wird - das sonst übliche "Service wird beim Verlassen der Seite
disposed" würde eine laufende Aufzeichnung sonst abbrechen. `TrackPage`
selbst wird beim Tab-Wechsel weiterhin ganz normal neu erzeugt - das
betrifft dann aber nur ihren eigenen UI-Zustand (Kartenausschnitt,
geladene Liste gespeicherter Tracks), nicht die Aufzeichnung selbst.

**Speicherung (`services/track_storage_service.dart`):** Jeder
gespeicherte Track landet als einzelne JSON-Datei (`<Startzeit in
Millisekunden>.json`) im app-eigenen Dokumentenverzeichnis (Paket
`path_provider`, neu zu `pubspec.yaml` hinzugefügt). Bewusst eine Datei
pro Track statt einer gemeinsamen Datenbank - für die in einer
Alltags-App zu erwartende Anzahl an Tracks (einige Dutzend bis wenige
Hundert) ein einfacher, robuster Ansatz, der zudem einzelne beschädigte
Dateien beim Laden überspringen kann, ohne die gesamte Liste zu
gefährden.

**Aufzeichnung/Bedienung (`ui/track_page.dart`):**
- Live-Karte mit der bisher aufgezeichneten Strecke als rote Linie sowie
  einem Marker an der aktuellen Position - dieselbe umschaltbare
  Landkarte/Seekarte inkl. Nordausrichtungs-Fixierung wie die frühere
  eigenständige Kartenseite, jetzt aus den gemeinsamen Bausteinen
  `widgets/map_tile_layers.dart`, `widgets/nautical_mode_button.dart` und
  `widgets/north_lock_button.dart` aufgebaut (siehe Abschnitt 9).
- Statuskarte unten mit Dauer, Distanz und Durchschnittstempo, sobald eine
  Aufzeichnung läuft oder pausiert ist.
- Bedienleiste ganz unten je nach Zustand: "Aufzeichnung starten" (idle)
  bzw. "Pause"/"Beenden" (recording) bzw. "Fortsetzen"/"Beenden" (paused).
  Beim Beenden fragt ein Dialog nach dem Tracknamen und ob gespeichert
  oder verworfen werden soll.
- Buttons oben rechts (von oben nach unten): eine Liste aller gespeicherten
  Tracks (Name, Datum, Distanz, Dauer; ein Papierkorb-Symbol daneben löscht
  den jeweiligen Track direkt aus der Liste heraus nach Bestätigung,
  Antippen eines Tracks öffnet stattdessen die neue
  **`ui/track_detail_page.dart`**, siehe unten, als eigene, per
  `Navigator.push` geöffnete Seite), die Landkarte/Seekarte-Umschaltung
  sowie die Nordausrichtungs-Fixierung (siehe Abschnitt 9).
- Bildschirm bleibt nur während AKTIVER Aufzeichnung wach (analog zur
  Tacho-/Kompass-Seite, siehe Abschnitt 7) - während einer Pause darf er
  wie gewohnt automatisch sperren.

**Detailansicht (`ui/track_detail_page.dart`):** Ersetzt die frühere,
eigenständige "Karte"-Seite (siehe Abschnitt 9) und zeigt einen einzelnen
gespeicherten Track vollständig an:
- Dieselbe umschaltbare Landkarte/Seekarte inkl. Nordausrichtungs-
  Fixierung wie bei der Aufzeichnung, beim Öffnen automatisch passend auf
  den gesamten Streckenverlauf eingerahmt (`MapController.fitCamera`, mit
  etwas Rand über `CameraFit.bounds`).
- Start- und Endpunkt des Tracks sind mit eigenen Markern
  (`Icons.trip_origin` bzw. `Icons.flag`) gekennzeichnet, dazwischen die
  komplette Strecke als rote Linie.
- Statuskarte unten mit Datum, Distanz, Dauer und Durchschnittstempo.
- Ein Löschen-Symbol in der oberen App-Leiste erlaubt das Löschen direkt
  aus der Detailansicht heraus (mit Bestätigungsdialog); die Seite
  schließt sich danach automatisch und signalisiert `TrackPage` per
  Rückgabewert, die Liste gespeicherter Tracks neu zu laden.

**Bekannte Einschränkung:** Wird die App vollständig in den Hintergrund
gelegt (nicht nur ein anderer Tab innerhalb der App), kann das
Betriebssystem die GPS-Aktualisierungsrate reduzieren oder den Prozess
irgendwann beenden - eine zuverlässige Aufzeichnung über Stunden hinweg
bei komplett gesperrtem Bildschirm würde einen Foreground-Service
erfordern, der bewusst nicht Teil dieser Umsetzung ist (ähnlich wie das
vorausschauende Kartenherunterladen in Abschnitt 8 wäre das eine deutlich
größere Ausbaustufe).

## 20. Track-Import/-Export im GPX-Format

Gespeicherte Tracks liegen zwar dauerhaft im app-eigenen
Dokumentenverzeichnis (siehe Abschnitt 19), das übersteht zwar normale
App-Updates, nicht aber z. B. eine Deinstallation oder einen
Gerätewechsel. Für genau diesen Fall - sowie zum Weiterverwenden von
Tracks in anderen Programmen bzw. zum Importieren von dort - gibt es
Export und Import im **GPX-Format** (GPS Exchange Format, offener,
XML-basierter Standard, u. a. von Google Earth, Strava, Komoot und
OsmAnd lesbar).

**Keine zusätzliche Android-Konfiguration nötig:** Weder `file_picker`
noch `share_plus` benötigen über die bereits in Abschnitt 2 beschriebenen
Einträge hinaus weitere manuelle Ergänzungen in der
`AndroidManifest.xml` - `file_picker` nutzt die Storage Access Framework
des Betriebssystems (kein Laufzeit-Berechtigungsdialog für den
Dateizugriff selbst nötig), und die für `share_plus` erforderliche
`FileProvider`-Konfiguration bringt das Paket über sein eigenes,
automatisch eingebundenes Manifest-Fragment bereits mit.


**Konvertierung (`util/gpx_converter.dart`):** Reine, zustandslose
Umwandlungslogik ohne jegliche Datei-Ein-/Ausgabe (dafür ist
`TrackImportExportService` zuständig, siehe unten) - das hält sie einfach
testbar. Für den Export wird die Track-Struktur (Name, Zeitstempel,
Trackpunkte inkl. Höhe) in ein GPX-1.1-Dokument mit `<trk><trkseg>
<trkpt>`-Elementen übersetzt (Paket `xml`, `XmlBuilder`). Für den Import
werden umgekehrt alle `<trkpt>`-Elemente ausgelesen (per
`findAllElements` rekursiv über das gesamte Dokument - mehrere
`<trkseg>` innerhalb eines `<trk>`, wie sie z. B. bei zwischenzeitlichem
GPS-Signalverlust entstehen können, werden dabei bewusst NICHT gesondert
behandelt, sondern als eine durchgehende Strecke zusammengefasst), daraus
Distanz (`Geolocator.distanceBetween`, punktweise aufsummiert) und Dauer
neu berechnet. Fehlt in einzelnen `<trkpt>` der optionale Zeitstempel,
wird ersatzweise eine Sekunde nach dem vorherigen Punkt angenommen, statt
den Import abzubrechen - die zeitliche Reihenfolge bleibt so in jedem
Fall plausibel. Der Name wird bevorzugt aus `<trk><name>`, sonst aus
`<metadata><name>` übernommen, andernfalls kommt der übliche
"Track vom TT.MM.JJJJ, HH:MM"-Vorschlag zum Einsatz (siehe
`TrackFormatter.suggestName`, Abschnitt 19). Die ID eines importierten
Tracks wird - konsistent mit einer selbst aufgezeichneten - aus dem
Startzeitpunkt abgeleitet: Ein wiederholter Import derselben Datei
überschreibt so denselben, bereits importierten Track, statt Duplikate
anzulegen.

**Ein-/Ausgabe (`services/track_import_export_service.dart`):**
- **Export:** Schreibt die GPX-Datei zunächst in das app-eigene,
  temporäre Verzeichnis (`path_provider`, `getTemporaryDirectory()`) und
  öffnet anschließend den nativen Android-"Teilen"-Dialog (Paket
  `share_plus`, `Share.shareXFiles`) - darüber lässt sich die Datei z. B.
  in der Dateien-App dauerhaft speichern, per Mail verschicken oder direkt
  in eine andere GPS-App übernehmen. Bewusst KEIN direktes Schreiben in
  einen für den Nutzer sichtbaren Ordner - dafür wäre unter aktuellem
  Android die Zustimmung des Nutzers über die Storage Access Framework
  nötig, der Teilen-Dialog deckt "dauerhaft irgendwo speichern" über
  "In Dateien speichern" bereits mit ab.
- **Import:** Öffnet den nativen Datei-Auswahl-Dialog (Paket
  `file_picker`, auf die Endung `.gpx` beschränkt). Speichert den
  importierten Track NICHT selbst - das obliegt der aufrufenden Seite
  (`TrackPage`), damit diese anschließend die Liste neu laden und eine
  Bestätigung anzeigen kann.

**Bedienung:**
- **Export:** Sowohl in der Liste gespeicherter Tracks (`TrackPage`, ein
  Teilen-Symbol neben dem Löschen-Symbol je Eintrag) als auch direkt in
  der Detailansicht (`TrackDetailPage`, Teilen-Symbol in der oberen
  App-Leiste) verfügbar.
- **Import:** Über ein Symbol neben der Überschrift "Gespeicherte Tracks"
  in der entsprechenden Liste (`TrackPage`) - nach erfolgreichem Import
  erscheint eine kurze Bestätigung, bei einer ungültigen/unlesbaren Datei
  eine verständliche Fehlermeldung statt eines Absturzes.

**Bewusst NICHT umgesetzt:** ein automatischer Import beim Öffnen einer
`.gpx`-Datei aus einer anderen App heraus (dafür wäre eine Registrierung
als Datei-Handler über einen `intent-filter` in der
`AndroidManifest.xml` sowie das Entgegennehmen des dabei übergebenen
Android-Intents nötig) - der manuelle Import über den
Datei-Auswahl-Dialog deckt den Anwendungsfall bereits ab, ohne die
Android-Konfiguration zusätzlich zu verkomplizieren. Bei Bedarf lässt
sich das jederzeit ergänzen.
