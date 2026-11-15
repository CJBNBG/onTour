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
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

`INTERNET` wird für das Laden der Kartenkacheln (OpenStreetMap/OpenSeaMap)
benötigt, die beiden Standort-Berechtigungen für Tacho, Track und die
Satellitenanzahl. Für den Beschleunigungssensor (Stillstandserkennung,
Abschnitt 6) ist unter Android KEINE gesonderte Berechtigung nötig.

**NEU - für die Hintergrund-Aufzeichnung von Tracks (siehe Abschnitt
19):** `FOREGROUND_SERVICE` wird seit Android 9 für jeden
Foreground-Service benötigt, `FOREGROUND_SERVICE_LOCATION` zusätzlich ab
Android 14 (API 34) speziell für einen Foreground-Service vom Typ
"location" - `geolocator` startet einen solchen automatisch, sobald ein
`ForegroundNotificationConfig` übergeben wird (siehe
`TrackRecordingService._startListening`). `POST_NOTIFICATIONS` wird ab
Android 13 (API 33) für JEDE Benachrichtigung benötigt, also auch für
die dauerhafte Hinweis-Benachrichtigung während einer laufenden
Track-Aufzeichnung - ohne diese Berechtigung würde die Benachrichtigung
auf neueren Geräten stillschweigend nicht angezeigt (die Aufzeichnung
selbst läuft davon unabhängig trotzdem weiter, der Nutzer sieht davon
aber ohne die Benachrichtigung nichts).

**Fehlerkorrektur - `WAKE_LOCK` fehlte:** Die Foreground-Service-
Konfiguration setzt `enableWakeLock: true` (hält die CPU während der
Hintergrund-Aufzeichnung wach, siehe `TrackRecordingService`) - dafür
ist zwingend `android.permission.WAKE_LOCK` nötig. Fehlt sie, wirft
`geolocator` beim Start der Aufzeichnung eine `SecurityException`
("Neither user ... nor current process has android.permission.WAKE_LOCK"),
sichtbar im Log als `PlatformException` auf dem
`geolocator_updates_android`-EventChannel. `WAKE_LOCK` ist eine normale
("nicht gefährliche") Berechtigung - sie wird automatisch bei der
Installation gewährt, es ist KEINE Laufzeit-Abfrage nötig.

**Falls du die App im Google Play Store veröffentlichst:** Für
Foreground-Service-Berechtigungen des Typs "location" verlangt die Play
Console (seit Android 14) eine zusätzliche Begründung/Erklärung in der
App-Übersicht (Bereich "App-Inhalt" → "Berechtigungen für
App-Zugriffsanfragen" bzw. "Foreground-Service-Berechtigungen") - das
ist unabhängig vom eigentlichen Code und muss einmalig in der Play
Console selbst ausgefüllt werden.

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

**Ort (aktualisiert durch Abschnitt 24):** Einstellungen → Erweitert
(ursprünglich, vor Einführung der Unterreiter, direkt auf der
alleinigen Einstellungsseite).

Dort lässt sich unter "Genauigkeit der Geschwindigkeitsmessung" eine von
drei Stufen wählen (`models/speed_accuracy_mode.dart`,
`SpeedAccuracyMode`):

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

**Zweite Verwendung: automatische Pause der Track-Aufzeichnung.** Seit
einer späteren Erweiterung nutzt auch `TrackRecordingService` denselben
`MotionService` (siehe README Abschnitt 19) - hier aber nicht zur
Korrektur einer Anzeige, sondern um eine laufende Aufzeichnung
automatisch zu pausieren, solange Stillstand erkannt wird (z. B. an
einer Ampel), und automatisch fortzusetzen, sobald wieder Bewegung
erkannt wird. Eine manuell über den "Pause"-Button ausgelöste Pause wird
davon bewusst NICHT berührt - nur eine automatische Pause hebt sich bei
Bewegung von selbst wieder auf.

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

**Kursanzeige mit Label:** Der Gradangabe ist ein Label "Kurs: "
vorangestellt (z. B. "Kurs: 87°") - bewusst als Teil desselben
Text-Widgets, damit Label und Wert garantiert in derselben Schrift/-größe
erscheinen (`textTheme.displaySmall`).

**Genauigkeitsangaben in eigenen, größeren Text-Widgets:** Die
Genauigkeit von Kurs, Höhe UND (neu) Position stehen jeweils in einem
EIGENEN `AutoHyphenatingText`-Widget direkt unter dem zugehörigen
Hauptwert - NICHT im selben Text enthalten. Die Schriftgröße wird dafür
programmatisch berechnet (`_accuracyStyle`): ursprünglich ein Drittel
der `displaySmall`-Größe, auf Wunsch für bessere Lesbarkeit inzwischen
auf zwei Drittel (= etwa doppelt so groß wie zuvor) angehoben - die
Genauigkeit bleibt damit weiterhin klar kleiner als der Hauptwert, aber
deutlich besser lesbar als vorher.

**Genauigkeit der Position (neu):** Unterhalb von Breite/Länge zeigt die
Kompass-Seite jetzt zusätzlich die horizontale Positionsgenauigkeit an
(z. B. "Genauigkeit: ± 8 m") - bewusst nur EINE gemeinsame Zeile für
Breite UND Länge (nicht getrennt), da ein GPS-Fix nur eine gemeinsame
horizontale Genauigkeit liefert. Dafür wurde `AltitudeReading` um
`positionAccuracyMeters` erweitert (aus `Position.accuracy`, analog zu
`latitude`/`longitude` - siehe Abschnitt zur Positionsanzeige weiter
unten) und `BarometerAltitudeService.calibrate()` reicht auch diesen
Wert als zusätzlichen, optionalen Parameter durch.

**Höhenanzeige:** Unterhalb der Peilungsgenauigkeit zeigt die
Kompass-Seite zusätzlich die aktuelle Höhe inkl. Quelle an - in derselben
Schriftgröße wie die Kursangabe (`displaySmall`) und als Meter über
Normal-Null angegeben ("... m ü. NN", z. B. "Höhe: 512 m ü. NN"; die
zugehörige Genauigkeit z. B. "Genauigkeit: ± 8 m (GPS)" erscheint separat
darunter, siehe oben). Zwei kombinierte Quellen:

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
dessen präzisere Werte (z. B. "Höhe: 512,3 m ü. NN", Genauigkeit
separat darunter: "Genauigkeit: ± 0,3 m (Barometer)"), andernfalls
bleibt es bei der GPS-Höhe (z. B. "Höhe: 512 m ü. NN" /
"Genauigkeit: ± 8 m (GPS)"). Weitere Design-Entscheidungen:
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

**Positionsanzeige (Breite/Länge, DMS-Format):** Unterhalb der Höhe
zeigt die Kompass-Seite zusätzlich die aktuelle Position an - Breiten-
und Längengrad JEWEILS in einer eigenen Zeile, in derselben Schriftgröße
wie die Kursangabe (`displaySmall`), z. B. "Breite: 52° 37' 12,3" N"
bzw. "Länge: 9° 13' 45,6" O". Formatiert wird über den neuen
`util/coordinate_formatter.dart` (`CoordinateFormatter`), der
Dezimalgrad in das im Outdoor-/Nautikbereich gebräuchlichere DMS-Format
(Grad/Minuten/Sekunden) umrechnet - passend zur nautischen Zielgruppe
der App (siehe Projektbeschreibung). "O" statt "E" für Ost, entsprechend
der deutschsprachigen Ausrichtung der App.

Die Position stammt bewusst aus DERSELBEN GPS-Messung wie die Höhe
(`AltitudeReading` wurde dafür um `latitude`/`longitude` erweitert,
siehe `models/altitude_reading.dart`) statt über einen weiteren, eigenen
Standort-Stream - das spart zusätzlichen GPS-/Akkuverbrauch. Auch die
vom Barometer gelieferten `AltitudeReading`s führen dafür jetzt die
zuletzt bekannte Position mit (`BarometerAltitudeService.calibrate()`
nimmt Breite/Länge inzwischen als zusätzliche Parameter entgegen), damit
die Positionsanzeige unabhängig davon funktioniert, ob gerade die
GPS- oder die Barometer-Höhe angezeigt wird. Fehlt die
Standort-Berechtigung bzw. liegt noch kein Wert vor, erscheint
konsequent "Breite: nicht verfügbar" bzw. "Länge: nicht verfügbar" -
analog zur Höhenanzeige. Direkt darunter steht (neu) eine gemeinsame
Genauigkeitszeile für die Position (`Position.accuracy`, als
`positionAccuracyMeters` ebenfalls über `AltitudeReading`
durchgereicht) - siehe "Genauigkeit der Position" weiter oben.

**Seitenlayout (Kompassrose oben, Textblock unten, freier Bereich
dazwischen, größenadaptiv):** Kompassrose und Textblock (Kurs, Höhe,
Position) sitzen in einem `Stack` an festen Positionen - die
Kompassrose oben (`Align(alignment: Alignment.topCenter)`), der
komplette Textblock unten (`Align(alignment: Alignment.bottomCenter)`,
direkt oberhalb der unteren Navigationsleiste aus `HomeShell`). Damit
beide Blöcke auf JEDER Bildschirmgröße UND bei JEDER Systemschriftgröße
garantiert nicht überlappen (das war mit rein festen Größen/Schriften
nicht zuverlässig der Fall - insbesondere Samsung-Geräte haben oft eine
größere Standard-Systemschrift), wird der verfügbare Platz jetzt per
`LayoutBuilder` zur Laufzeit gemessen:

- Die Kompassrose bekommt eine berechnete Kantenlänge - orientiert an
  der verfügbaren Breite, aber auf max. ca. 48 % der verfügbaren Höhe
  begrenzt (`120`-`360` logische Pixel, siehe Abschnitt 28 für eine
  spätere Anhebung dieser Werte), damit für den Textblock in jedem Fall
  genug Platz übrig bleibt.
- Der komplette Textblock wird über `FittedBox(fit: BoxFit.scaleDown)`
  in den verbleibenden Platz eingepasst - ist genug Platz vorhanden,
  bleibt die reguläre `displaySmall`-Schriftgröße erhalten; nur bei
  Platzmangel (großer Systemschrift, kleiner Bildschirm) wird der GESAMTE
  Block gleichmäßig verkleinert, wodurch das Größenverhältnis zwischen
  Hauptwerten und den ein Drittel so großen Genauigkeitsangaben
  (`_accuracyStyle`) erhalten bleibt.

Der Textblock selbst ist dafür in eine eigene Methode
(`_buildTextBlock`) ausgelagert, damit `build()` ihn unverändert per
`FittedBox` skalieren kann.


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
- **Nachkommastellen-Darstellung (aktualisiert):** `SpeedFormatter`
  formatiert jetzt IMMER mit genau einer Nachkommastelle (frühere Regel
  "unterhalb von 10 km/h eine Nachkommastelle, sonst keine" wurde
  aufgegeben). `SpeedPage._buildSpeedNumber` trennt diese eine
  Nachkommastelle vom Vorkommateil ab und zeigt sie deutlich kleiner
  (ca. ein Drittel der Höhe) und hochgestellt direkt hinter der Zahl an
  (zwei nebeneinander gesetzte `SevenSegmentDisplay`-Instanzen
  unterschiedlicher Höhe in einer `Row` mit `crossAxisAlignment.start`).
- **Info-Zeilen besser lesbar (aktualisiert):** Die drei Zeilen unterhalb
  der Einheiten-Angabe (Geschwindigkeits-Genauigkeit, Satellitenanzahl,
  Stillstands-/Messungs-Status) nutzen jetzt `_readableInfoStyle` -
  programmatisch auf das Doppelte der ursprünglichen `bodySmall`-Größe
  berechnet, statt der vorherigen, recht kleinen Standardgröße. Das war
  bislang während der Fahrt (Blick nur kurz auf das Display) schwer
  lesbar.
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
  - Das tatsächliche App-Icon (`assets/icon/icon.png`, dieselbe Datei,
    aus der auch das Launcher-Icon erzeugt wird, siehe Abschnitt 14)
    statt eines generischen Material-Icons - dafür ist die Datei jetzt
    zusätzlich unter `flutter/assets` in `pubspec.yaml` eingetragen
    (zuvor nur für `flutter_launcher_icons` konfiguriert, nicht als
    regulärer App-Asset nutzbar). **Wichtig:** Nach dieser
    pubspec-Änderung reicht ein reines Hot Reload nicht aus - neu
    deklarierte Assets werden erst nach einem Hot Restart bzw.
    kompletten Neustart der App eingebunden. Falls die Datei zur
    Laufzeit trotzdem nicht gefunden werden kann (z. B. abweichender
    Dateiname/-pfad), fängt ein `errorBuilder` das ab und zeigt
    ersatzweise wieder das bisherige, generische Icon - so führt ein
    fehlendes Asset nicht zu einem Absturz der Info-Seite.
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
(`initHyphenation(DefaultResourceLoaderLanguage.de1996)`). VIER bewusste
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
- **NEU (Fehlerkorrektur):** `title`, `content` UND die `TextButton`-/
  `FilledButton`-Aktionen in ALLEN DREI `AlertDialog`s des Projekts
  (Track beenden in `track_page.dart`, Track löschen in `track_page.dart`
  UND `track_detail_page.dart`) verwenden aus demselben Grund wie beim
  `SegmentedButton` durchgängig normales `Text` statt
  `AutoHyphenatingText`. Flutters interne Dialog-Layout-Mechanik führt an
  MEHREREN Stellen intrinsische Breitenberechnungen durch, die mit
  `AutoHyphenatingText`s `LayoutBuilder`-Ansatz kollidieren:
  - Die `actions` werden über ein `OverflowBar` angeordnet, das bei zu
    wenig Platz (z. B. drei Buttons, einer mit dem längeren Text "Weiter
    aufzeichnen") die intrinsische Breite jedes Buttons berechnet, um zu
    entscheiden, ob umgebrochen werden muss.
  - Bei `scrollable: true` (siehe "Aufzeichnung beenden"-Dialog) packt
    Flutter zusätzlich `title` UND `content` GEMEINSAM in einen
    scrollbaren Bereich, der ebenfalls Teil derselben intrinsischen
    Breitenberechnung ist wie die Aktionsleiste.

  Eine erste, unvollständige Korrektur (nur die `actions`) behob den
  Laufzeitfehler ("LayoutBuilder does not support returning intrinsic
  dimensions" bzw. "RenderBox was not laid out") deshalb noch NICHT
  zuverlässig - erst nachdem auch `title` konsequent auf `Text`
  umgestellt wurde, verschwand der Fehler vollständig. Bei so kurzen
  Dialog-Texten wäre eine Silbentrennung ohnehin nie nötig gewesen -
  generelle Regel seither: **In `AlertDialog`s grundsätzlich kein
  `AutoHyphenatingText` verwenden, weder für `title`, `content` noch
  `actions`.**

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
    coordinate_formatter.dart  Formatierung von Breite/Länge im DMS-Format
                                (Abschnitt 10, Kompass-Seite)
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

**Fehlerkorrektur - Liste aktualisiert sich nach dem Löschen sofort:**
Die Liste gespeicherter Tracks wird über `showModalBottomSheet` als
eigene, vom übrigen Widget-Baum der Seite losgelöste Route dargestellt -
ein normales `setState` auf `_TrackPageState` (wie es `_loadSavedTracks`
nach dem Löschen aufruft) baut deshalb NICHT automatisch das bereits
geöffnete Sheet neu auf; der gelöschte Track blieb dort fälschlich
sichtbar, bis das Sheet geschlossen und erneut geöffnet wurde. Ein
`StatefulBuilder` um den Sheet-Inhalt stellt jetzt einen eigenen,
lokalen Rebuild-Callback (`setModalState`) bereit, den `_handleDelete`
zusätzlich zum normalen `setState` aufruft - der Import-Button ist davon
nicht betroffen, da er das Sheet ohnehin sofort schließt, bevor der
eigentliche Import beginnt (siehe unten).

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

**Zusammenspiel von manueller und automatischer Pause (Fehlerkorrektur):**
Ein manuelles Antippen von "Pause" wirkt jetzt auch dann, wenn die
Aufzeichnung bereits AUTOMATISCH pausiert ist (z. B. weil man während
einer automatischen Stillstands-Pause an einer Ampel zusätzlich selbst
auf "Pause" tippt, etwa um eine längere Rast einzulegen) -
`TrackRecordingService.pause()` markiert die laufende Pause in diesem
Fall nachträglich als manuell, statt (wie in einer früheren Version)
wirkungslos zu bleiben. Ohne diese Korrektur blieb eine solche Pause
intern fälschlich als "automatisch" eingestuft, wodurch ein bloßes
In-die-Hand-Nehmen des Telefons (vom Bewegungssensor bereits als
Bewegung gewertet) sie ungewollt sofort wieder automatisch aufhob, noch
bevor der "Fortsetzen"-Button überhaupt angetippt werden konnte - ein
spürbar "hakeliges" Verhalten.

Zusätzlich sorgt eine kurze **Schonfrist von 10 Sekunden** nach einem
MANUELLEN Antippen von "Fortsetzen" (`TrackRecordingService.resume`,
Parameter `manual`) dafür, dass die automatische Stillstandserkennung in
diesem Zeitfenster ausgesetzt ist - andernfalls hätte die automatische
Pause sofort wieder zugeschlagen, wenn das Fahrzeug im Moment des
Antippens noch nicht tatsächlich losgefahren war. Ein automatisches
Fortsetzen (durch erkannte Bewegung nach einer automatischen Pause,
siehe oben) setzt diese Schonfrist bewusst NICHT - sie gilt
ausschließlich für den expliziten Tap auf den Button.

**Bedienelemente bei automatischer Pause (aktualisiert):** "Pause" und
"Fortsetzen" sind funktional unabhängige Aktionen (siehe oben) - deshalb
zeigt `TrackPage._buildControls` während einer AUTOMATISCHEN Pause jetzt
BEIDE Buttons gleichzeitig an ("Pause", "Fortsetzen" UND "Beenden", drei
statt zwei Buttons in der Reihe): Ein Tap auf "Pause" fixiert die
laufende Pause als manuell (siehe oben), OHNE die Aufzeichnung
fortzusetzen - nützlich, um eine automatische Pause bewusst zu
"bestätigen", bevor sie durch eine kurze Bewegung (z. B. beim
In-die-Hand-Nehmen des Telefons) ungewollt automatisch wieder aufgehoben
wird. Bei einer bereits MANUELLEN Pause wäre ein zusätzlicher
"Pause"-Tap dagegen wirkungslos (siehe `TrackRecordingService.pause`)
und wird deshalb dort weiterhin nicht angeboten - nur "Fortsetzen" und
"Beenden" wie bisher.

**Aufzeichnung im Hintergrund (Foreground-Service):** Wird onTour
während einer laufenden Aufzeichnung in den Hintergrund gelegt (nicht
nur ein anderer Tab innerhalb der App, sondern z. B. weil kurz Google
Maps zur Navigation geöffnet wird), bricht die Aufzeichnung NICHT ab.
`TrackRecordingService._startListening` konfiguriert den GPS-Stream
dafür über `AndroidSettings`/`ForegroundNotificationConfig` (Paket
`geolocator`) als nativen Android-Foreground-Service mit einer
dauerhaften, nicht wegwischbaren Benachrichtigung ("onTour zeichnet
auf ...") - das signalisiert dem Betriebssystem, dass die App aktiv
weiterarbeiten soll, und verhindert zuverlässig, dass Android die
GPS-Aktualisierungsrate drosselt oder den Prozess beendet. Die
zugehörigen Berechtigungen sind in Abschnitt 2 beschrieben.

Der Foreground-Service läuft dabei exakt so lange wie der GPS-Stream
selbst - also NUR während `RecordingState.recording`. Bei einer Pause
(egal ob manuell über den Button oder automatisch bei erkanntem
Stillstand, siehe oben) wird der Stream wie gehabt beendet, wodurch
auch der Foreground-Service und damit die Benachrichtigung
verschwinden - das spart während einer Pause weiterhin Akku und ist
bewusst keine Ausnahme für die neue Hintergrundfunktion.

**Hinweis zu herstellerspezifischem Akku-Management:** Trotz
Foreground-Service können manche Android-Hersteller (insbesondere
Samsung mit seinem sehr aggressiven Akku-/Ruhezustands-Management)
Apps im Hintergrund dennoch beenden. Für eine zuverlässige
Langzeitaufzeichnung empfiehlt es sich, onTour in den
Geräteeinstellungen manuell von der Akku-Optimierung auszunehmen (z. B.
unter "Einstellungen → Apps → onTour → Akku → Nicht optimieren" bzw.
das entsprechende Samsung-Pendant "Nicht überwachte Apps") - das ist
eine reine Geräteeinstellung außerhalb der App selbst.

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

## 21. Aufzeichnung übersteht ein Entfernen der App aus den zuletzt verwendeten Apps

**Problem, das hiermit behoben wird:** Bislang konnte eine laufende
Track-Aufzeichnung "einfrieren", ohne dass das äußerlich erkennbar war:
Wischt man onTour während einer Aufzeichnung aus der Liste der zuletzt
verwendeten Apps ("Recents"), blieb zwar die Benachrichtigung des
nativen Android-Foreground-Service sichtbar (siehe Abschnitt 19) UND der
zugrunde liegende GPS-Empfang lief nativ tatsächlich weiter - aber ohne
die hier beschriebene Änderung zerstört Android beim Entfernen der
App-Kachel standardmäßig sowohl `MainActivity` als auch die zu ihr
gehörende `FlutterEngine`. Der GESAMTE Dart-Zustand - insbesondere alle
bereits gesammelten `TrackPoint`s, die aufsummierte Distanz und die
Dauer, die ausschließlich im Arbeitsspeicher von
`TrackRecordingService` liegen (siehe Abschnitt 19) - ging dabei
verloren. Die Benachrichtigung suggerierte also eine weiterlaufende
Aufzeichnung, obwohl tatsächlich keine neuen Punkte mehr im Dart-Code
ankamen und beim nächsten Öffnen der App eine "leere", neu erzeugte
`TrackRecordingService`-Instanz vorlag.

**Ursache:** Das ist normales, von Flutter selbst so vorgesehenes
Verhalten für den Standardfall (`FlutterActivity` erzeugt bei jedem
Start automatisch eine NEUE `FlutterEngine` und zerstört sie beim
eigenen Beenden wieder mit) - unabhängig davon, ob der zugrunde liegende
native Android-Service (hier: der geolocator-Foreground-Service) selbst
über ein Wischen hinaus weiterläuft oder nicht (`android:stopWithTask`
ist laut offizieller Android-Dokumentation für Services standardmäßig
bereits `false`, betrifft hier also gar nicht das eigentliche Problem).
Das Problem liegt ausschließlich auf der Flutter-Engine-/Activity-Ebene.

**Lösung - eine einzige, app-weite, dauerhafte FlutterEngine:** Statt
bei jedem `MainActivity`-Start eine neue Engine zu erzeugen, wird jetzt
GENAU EINE `FlutterEngine` bereits beim Start des Android-**Prozesses**
erzeugt (`native_android/de/clausjbauer/ontour/OnTourApplication.kt`,
neue Datei) und im `FlutterEngineCache` abgelegt. `MainActivity`
verwendet ausschließlich diese eine, geteilte Engine
(`provideFlutterEngine`) und zerstört sie beim eigenen Beenden
ausdrücklich NICHT mit (`shouldDestroyEngineWithHost` liefert `false`,
`cleanUpFlutterEngine` bleibt leer). Der zugrunde liegende Dart-Isolate -
und damit der komplette In-Memory-Zustand der App, allen voran
`TrackRecordingService` - lebt dadurch unabhängig von `MainActivity`
weiter, solange der Android-**Prozess** selbst am Leben bleibt.

**WICHTIG - das allein reicht NICHT aus, sondern wirkt nur in
Kombination mit dem bereits vorhandenen Foreground-Service:** Eine
dauerhafte Engine verhindert für sich genommen nicht, dass Android den
kompletten Prozess unter Speicherdruck beendet, sobald keine sichtbare
Activity mehr existiert - ein Prozess ohne jede Activity UND ohne
laufenden Service zählt für Android zu den ZUERST zu beendenden
("cached") Prozessen. Entscheidend ist daher das Zusammenspiel mit dem
bereits in Abschnitt 19 beschriebenen Foreground-Service: Solange
tatsächlich aufgezeichnet wird (`RecordingState.recording`), stuft
Android den Prozess wegen des laufenden Foreground-Service als hohe
Priorität ein und beendet ihn unter normalem Speicherdruck praktisch
nie - unabhängig davon, ob gerade eine Activity existiert. Die
persistente Engine sorgt in dieser Situation lediglich dafür, dass der
Dart-Code, der die GPS-Punkte tatsächlich entgegennimmt und verarbeitet,
währenddessen ebenfalls am Leben bleibt, statt mit `MainActivity`
zerstört zu werden. Ohne eine aktive Aufzeichnung (kein Foreground-
Service) bietet diese Änderung dementsprechend KEINEN zusätzlichen
Schutz vor einem Prozessende - das ist in diesem Fall aber auch nicht
nötig, da dann ohnehin kein App-Zustand verloren gehen kann, der nicht
auch durch einen normalen Neustart der App wiederhergestellt würde.

**Notwendige Anpassung in `AndroidManifest.xml`:** Damit Android die
neue `OnTourApplication`-Klasse tatsächlich verwendet, muss dem
`<application>`-Tag zusätzlich das Attribut `android:name` gesetzt
werden:

```xml
<application
    android:name=".OnTourApplication"
    android:label="onTour"
    ...>
```

(Falls dein Projekt bereits eine eigene Application-Klasse hat -
z. B. weil sie ein anderes Paket dafür benötigt -, übertrage stattdessen
den Inhalt der `onCreate()`-Methode aus `OnTourApplication.kt` in deine
bestehende Klasse, statt beide parallel zu verwenden; Android erlaubt
pro App nur eine aktive Application-Klasse.)

**Nebenbemerkung zur Bildschirmausrichtung:** `main()` (siehe
`main.dart`) läuft durch diese Änderung jetzt bereits beim Start des
Android-Prozesses, also VOR der ersten Activity - inhaltlich unschädlich
(die dortigen Initialisierungen wie Silbentrennung oder
Datumsformatierung laufen dadurch lediglich etwas früher, nicht öfter),
mit EINER Ausnahme: Der Aufruf
`SystemChrome.setPreferredOrientations([...])` benötigt intern eine
bereits vorhandene Activity, um die Ausrichtung tatsächlich zu setzen,
und könnte deshalb bei diesem allerersten, noch activity-losen Aufruf
wirkungslos verpuffen (ohne Absturz, nur ohne Effekt). Als robusten,
von diesem zeitlichen Ablauf unabhängigen Ersatz sollte deshalb
zusätzlich `android:screenOrientation="portrait"` direkt am
`<activity>`-Tag von `MainActivity` in der `AndroidManifest.xml` gesetzt
werden:

```xml
<activity
    android:name=".MainActivity"
    android:screenOrientation="portrait"
    ...>
```

Das erzwingt die Hochkantausrichtung bereits auf Betriebssystemebene,
unabhängig davon, wann bzw. ob der Dart-seitige `SystemChrome`-Aufruf
tatsächlich greift - der Aufruf in `main.dart` kann trotzdem unverändert
bestehen bleiben (schadet nicht, ist nur nicht mehr die alleinige
Absicherung).

**Betroffene/neue Dateien:**
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt` (NEU)
- `native_android/de/clausjbauer/ontour/MainActivity.kt` (ersetzt die
  bisherige Version 1:1, siehe Abschnitt 3 für den Kopiervorgang -
  enthält weiterhin unverändert die GNSS-Satellitenanzahl-Logik)
- `AndroidManifest.xml` (zwei neue Attribute, siehe oben)

**Zum Testen (am besten auf dem Samsung S23 Ultra, wie gewohnt):**
Aufzeichnung starten → App über die "Zuletzt verwendete Apps"-Übersicht
aus der Liste wischen → einige Minuten warten (idealerweise mit
tatsächlicher Bewegung, damit neue Punkte hinzukommen) → App erneut
öffnen. Distanz, Dauer und Punktezahl sollten nahtlos weitergezählt
haben, statt bei 0 neu zu beginnen. Für den in Abschnitt 19 bereits
beschriebenen Sonderfall herstellerspezifischer Akku-Optimierung (die
diese Absicherung umgehen kann) gilt weiterhin die dortige Empfehlung,
onTour manuell von der Akku-Optimierung auszunehmen.

## 22. Erinnerung bei anhaltend pausierter Track-Aufzeichnung

**Motivation:** Eine automatisch (Stillstand, siehe Abschnitt 6/19) oder
manuell pausierte Track-Aufzeichnung lässt sich leicht "vergessen" - z. B.
zuhause angekommen, Smartphone eingesteckt, die App wird für längere Zeit
gar nicht mehr aktiv geöffnet. Der Foreground-Service läuft während einer
Pause bewusst NICHT weiter (spart Akku, siehe Abschnitt 19), die
Aufzeichnung selbst bleibt aber "offen" - der Nutzer bemerkt das im
schlechtesten Fall erst am spürbar niedrigeren Akkustand oder daran, dass
ein späterer Blick in die App eine unerwartet lange "Dauer" anzeigt.

**Umsetzung:** Bleibt eine Aufzeichnung länger als eine wählbare Wartezeit
ununterbrochen pausiert, erscheint eine Benachrichtigung ("Track-
Aufzeichnung pausiert - jetzt beenden?"), die beim Antippen die App
öffnet. Die Wartezeit ist unter Einstellungen → Erweitert wählbar (siehe
Abschnitt 24 für die Unterreiter-Struktur der Einstellungsseite;
`models/auto_pause_reminder_option.dart`, `AutoPauseReminderOption`: Aus/
10/20/30/45 Minuten, Standard 20 Minuten) und wird - analog zu den
übrigen Einstellungen, siehe Abschnitt 5 - über `AppPreferences`
persistiert. `TrackPage` hält `TrackRecordingService` dafür bei jedem
Rebuild über `updateReminderOption` mit dem aktuellen Wert synchron; eine
Änderung wirkt sich - analog zur Genauigkeitsstufe der
Geschwindigkeitsmessung, siehe Abschnitt 4 - erst auf die NÄCHSTE Pause
aus, nicht rückwirkend auf eine bereits laufende, bereits geplante
Erinnerung.

**WICHTIGE Architektur-Entscheidung - nativer `AlarmManager` statt
Dart-`Timer`:** Ein einfacher, in `TrackRecordingService` laufender
Dart-`Timer` wäre die naheliegendere Umsetzung gewesen, funktioniert hier
aber nicht zuverlässig: Genau während einer Pause existiert (bewusst,
siehe oben) kein Foreground-Service mehr - der Android-Prozess (und mit
ihm jeder darin laufende Dart-Timer, auch bei der persistenten Engine aus
Abschnitt 21) kann in dieser Zeit vom Betriebssystem jederzeit beendet
werden, sobald die App im Hintergrund ist. Die Erinnerung würde dann
ausgerechnet in den Fällen ausbleiben, vor denen sie eigentlich schützen
soll. Stattdessen wird der Alarm nativ über Androids `AlarmManager`
geplant (`native_android/de/clausjbauer/ontour/
AutoPauseReminderScheduler.kt`, neu) - ein solcher Alarm wird
systemseitig verwaltet und übersteht das Beenden des App-Prozesses
vollständig: Beim Auslösen startet Android bei Bedarf kurzzeitig einen
eigenen, minimalen Prozess für den zugehörigen `BroadcastReceiver`
(`AutoPauseReminderReceiver.kt`, neu), der die Benachrichtigung anzeigt -
unabhängig davon, ob die eigentliche App zu diesem Zeitpunkt noch läuft.

**Kommunikation Dart ↔ nativ:** Ein neuer `MethodChannel`
(`ontour/auto_pause_reminder`) mit den beiden Methoden `schedule`
(Parameter `delayMinutes`) und `cancel`. `TrackRecordingService` ruft
`schedule` in `_pauseInternal` auf (gemeinsamer Pfad für MANUELLE und
AUTOMATISCHE Pause - eine "vergessene" Aufzeichnung droht in beiden
Fällen gleichermaßen) und `cancel` in `resume`, `stop` sowie `discard`.
Ein Fehlschlag dieser Aufrufe (z. B. auf einer Plattform ohne die native
Implementierung) wird bewusst verschluckt statt weitergereicht - die
Erinnerung ist ein reiner Komfort-Zusatz, der die eigentliche
Aufzeichnung nicht beeinträchtigen darf.

**WICHTIG, warum der `MethodChannel`-Handler in `OnTourApplication` statt
in `MainActivity` registriert wird:** Eine Pause (und damit ein
Schedule-/Cancel-Aufruf) kann JEDERZEIT eintreten - auch dann, wenn
gerade gar keine Activity existiert (z. B. weil die App aus den zuletzt
verwendeten Apps entfernt wurde, siehe Abschnitt 21). Ein in
`MainActivity` registrierter Handler wäre in diesem Fall nicht erreichbar
bzw. müsste einen möglicherweise bereits zerstörten Activity-`Context`
verwenden. Der in `OnTourApplication` verwendete `applicationContext`
bleibt dagegen so lange gültig wie der Android-Prozess selbst.

**Bewusst `setAndAllowWhileIdle` statt einer exakten Alarm-Variante:**
Für eine reine Erinnerung ist eine durch den Doze-Modus verursachte
Verschiebung um einige Minuten unproblematisch - dafür ist im Unterschied
zu exakten Alarmen (`setExactAndAllowWhileIdle`) unter Android 12+ KEINE
gesonderte, vom Nutzer manuell zu erteilende "Alarme & Erinnerungen"-
Berechtigung (`SCHEDULE_EXACT_ALARM`) nötig.

**Notwendige Ergänzung in `AndroidManifest.xml`:** Der neue
`BroadcastReceiver` muss registriert werden (innerhalb von
`<application>`, analog zu den bestehenden Einträgen):

```xml
<receiver
    android:name=".AutoPauseReminderReceiver"
    android:exported="false" />
```

Zusätzliche Android-Berechtigungen sind NICHT nötig - `POST_NOTIFICATIONS`
(ab Android 13) ist bereits seit Abschnitt 2 vorhanden (dort ursprünglich
für die Foreground-Service-Benachrichtigung ergänzt) und deckt auch diese
neue Benachrichtigung mit ab; für `setAndAllowWhileIdle` ist - anders als
für exakte Alarme - keine gesonderte Berechtigung erforderlich (siehe
oben).

**Falls ein Compile-Fehler zu `androidx.core.app.NotificationCompat`
auftritt:** Das Symbol ist normalerweise bereits über Flutters eigene
AndroidX-Abhängigkeiten verfügbar; sollte es dennoch fehlen, in
`android/app/build.gradle` (bzw. `build.gradle.kts`) unter `dependencies`
ergänzen: `implementation("androidx.core:core-ktx:1.13.1")` (oder die
jeweils aktuelle Version).

**Direkter Sprung zum Track-Tab beim Antippen:** Siehe Abschnitt 23 -
diese ursprünglich als "bewusst nicht umgesetzt" zurückgestellte
Komfortfunktion wurde inzwischen nachgerüstet.

**Bemerkenswerte Nebeneigenschaft:** Der Alarm feuert unabhängig davon,
ob der App-Prozess zu diesem Zeitpunkt noch existiert (siehe oben) - sollte
der Prozess während einer Pause aus irgendeinem Grund dennoch beendet
werden (z. B. durch besonders aggressives herstellerspezifisches
Akku-Management, siehe Abschnitt 19), bekommt der Nutzer die Erinnerung
trotzdem zuverlässig angezeigt.

**Betroffene/neue Dateien:**
- `lib/models/auto_pause_reminder_option.dart` (NEU)
- `lib/services/app_preferences.dart` (neue Einstellung)
- `lib/services/track_recording_service.dart` (Schedule/Cancel-Aufrufe)
- `lib/ui/settings_page.dart` (neue Auswahl-Sektion, seit Abschnitt 24 im
  Unterreiter "Erweitert")
- `lib/ui/track_page.dart` (hält den Service mit der Einstellung synchron)
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt` (neuer
  MethodChannel-Handler)
- `native_android/de/clausjbauer/ontour/AutoPauseReminderScheduler.kt`
  (NEU)
- `native_android/de/clausjbauer/ontour/AutoPauseReminderReceiver.kt`
  (NEU)
- `AndroidManifest.xml` (neuer `<receiver>`-Eintrag, siehe oben)

## 23. Erinnerungs-Benachrichtigung führt direkt zum Track-Tab

**Motivation:** Die in Abschnitt 22 beschriebene Erinnerung öffnete beim
Antippen zunächst nur die App auf ihrem Start-Tab (Tacho, siehe Abschnitt
16) - der Nutzer musste danach selbst zum Track-Tab wechseln, um die
Aufzeichnung tatsächlich zu beenden oder fortzusetzen. Da genau diese
Bedienelemente ausschließlich dort liegen, führt ein Antippen jetzt
direkt zum Track-Tab.

**Umsetzung - Intent-Extra plus "Pull"-Abfrage statt direktem
Methodenaufruf:** `AutoPauseReminderReceiver` versieht den Klick-Intent
der Benachrichtigung mit einem zusätzlichen Extra
(`MainActivity.EXTRA_OPEN_TRACK_TAB`). `MainActivity` wertet dieses Extra
sowohl in `onCreate` (Activity existierte nicht mehr, z. B. nach einem
Wischen aus den zuletzt verwendeten Apps, siehe Abschnitt 21) als auch in
`onNewIntent` (Activity existiert noch, wird lediglich in den Vordergrund
geholt) aus und merkt sich das Ergebnis in einem neuen, rein
prozessinternen Objekt `PendingNavigation` (`openTrackTab: Boolean`).

Auf Dart-Seite fragt `HomeShell` diesen Zustand über einen neuen
`MethodChannel` (`ontour/navigation`, Methode
`consumePendingOpenTrackTab`) ab - sowohl beim eigenen Start
(`initState`) als auch bei jedem Zurückkehren in den Vordergrund
(`WidgetsBindingObserver.didChangeAppLifecycleState`,
`AppLifecycleState.resumed`). Liefert die Abfrage `true` zurück (und setzt
den nativen Zustand dabei zugleich zurück), wechselt `HomeShell` per
`setState` auf den Track-Tab (Index 2).

**WICHTIG, warum "Pull" (Dart fragt nach) statt "Push" (nativ ruft
proaktiv in Dart hinein):** Ein direkter `MethodChannel`-Aufruf aus
`MainActivity.onCreate` heraus, unmittelbar nachdem das Intent-Extra
erkannt wurde, wäre die naheliegendere Umsetzung gewesen. Bei einem
echten Kaltstart (App-Prozess war komplett beendet, wird erst durch
Antippen der Benachrichtigung neu gestartet) ist zu diesem sehr frühen
Zeitpunkt aber nicht garantiert, dass `HomeShell` ihren
`MethodChannel`-Handler bereits registriert hat - ein zu früher "Push"
würde dann folgenlos verpuffen (klassische Race Condition bei
plattformübergreifender Kommunikation direkt nach dem Start). Das
"Pull"-Modell umgeht das vollständig: `HomeShell` fragt aktiv nach,
sobald sie tatsächlich bereit ist, beliebig oft und ohne Zeitdruck.

**Notwendige Ergänzung in `AndroidManifest.xml`:** `MainActivity` muss
auf `launchMode="singleTask"` gesetzt werden, damit ein Antippen der
Benachrichtigung bei bereits existierender Activity zuverlässig
`onNewIntent` auf der VORHANDENEN Instanz auslöst, statt eine zweite,
parallele Instanz zu erzeugen (die sich sonst dieselbe, persistente
FlutterEngine aus Abschnitt 21 streitig machen würde):

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTask"
    ...>
```

**Betroffene/neue Dateien:**
- `native_android/de/clausjbauer/ontour/MainActivity.kt` (Intent-
  Auswertung in `onCreate`/`onNewIntent`)
- `native_android/de/clausjbauer/ontour/PendingNavigation.kt` (NEU)
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt` (neuer
  MethodChannel-Handler)
- `native_android/de/clausjbauer/ontour/AutoPauseReminderReceiver.kt`
  (Intent-Extra und -Flags beim Klick-Intent)
- `lib/ui/home_shell.dart` (Abfrage beim Start und bei jedem
  Vordergrund-Wechsel)
- `AndroidManifest.xml` (`launchMode="singleTask"`, siehe oben)

## 24. Einstellungsseite: Unterreiter "Anzeige" und "Erweitert"

**Motivation:** Mit der neuen Erinnerungs-Einstellung aus Abschnitt 22
wären auf der bisher einzigen, flachen Einstellungsseite drei inhaltlich
sehr unterschiedliche Einstellungen (Anzeigemodus, Genauigkeitsstufe der
Geschwindigkeitsmessung, Pause-Erinnerung) untereinander gestanden -
zunehmend unübersichtlich, zumal die beiden letztgenannten deutlich
seltener angefasst werden als der Anzeigemodus.

**Umsetzung:** `SettingsPage` (`lib/ui/settings_page.dart`) ist jetzt ein
`StatefulWidget` mit eigenem `TabController` (`SingleTickerProviderStateMixin`)
und zeigt zwei Unterreiter:

- **Anzeige**: bislang einzige Einstellung, der Anzeigemodus
  (System/Hell/Dunkel, siehe Abschnitt 5).
- **Erweitert**: die Genauigkeitsstufe der Geschwindigkeitsmessung (bisher
  Abschnitt 4) sowie die neue Pause-Erinnerung (Abschnitt 22) - beide
  eher technische Einstellungen, die man in der Regel einmal passend zum
  eigenen Gerät einstellt und danach kaum noch ändert.

Die Unterreiter sitzen bewusst INNERHALB der bestehenden Hauptseite
"Einstellungen" (`TabBar`/`TabBarView` im `build()` von `SettingsPage`,
unterhalb der von `HomeShell` weiterhin gemeinsam bereitgestellten
`AppBar`) - NICHT als zusätzlicher, fünfter Eintrag in der unteren
Navigationsleiste: Die Aufteilung ist rein organisatorisch eine Ebene
unterhalb von "Einstellungen", keine gleichberechtigte weitere Hauptseite
der App.

**Zur Beschriftung der Unterreiter:** Bewusst normale `Text`-Labels statt
`AutoHyphenatingText` - bei den hier kurzen, einzeiligen Bezeichnungen
("Anzeige", "Erweitert") wäre eine Silbentrennung ohnehin nie nötig,
analog zur bereits bestehenden Ausnahme bei `SegmentedButton` (siehe
Abschnitt 13).

**Keine Auswirkung auf persistierte Werte:** Alle drei Einstellungen
bleiben unverändert über `AppPreferences`/`shared_preferences`
persistiert (siehe Abschnitt 5) - die Umstrukturierung betrifft
ausschließlich die Darstellung, nicht die Speicherung.

**Betroffene Dateien:**
- `lib/ui/settings_page.dart` (grundlegend umgebaut: `StatelessWidget` →
  `StatefulWidget` mit `TabController`, Inhalte in `_buildDisplayTab`
  bzw. `_buildAdvancedTab` aufgeteilt)

## 25. Wählbares Positionsformat auf der Kompass-Seite (DMS/DMM/DD/UTM)

**Motivation:** Bislang war DMS (Grad/Minuten/Sekunden) das einzige,
fest einprogrammierte Anzeigeformat für die aktuelle Position auf der
Kompass-Seite. Je nach Hintergrund sind aber unterschiedliche Formate
gebräuchlich bzw. leichter mit vorhandenem Kartenmaterial abzugleichen -
UTM etwa in Vermessung und vielen (insbesondere militärisch geprägten
oder älteren) topografischen Karten, DD (Dezimalgrad) für die direkte
Eingabe in viele Online-Kartendienste.

**Umsetzung:** Eine neue Auswahl unter Einstellungen → Anzeige (siehe
Abschnitt 24), "Positionsformat (Kompass-Seite)"
(`models/position_display_format.dart`, `PositionDisplayFormat`):

| Format | Beispiel | Typischer Einsatzbereich |
|---|---|---|
| DMS (Standard) | 52° 37' 12,3" N | Nautik, Outdoor - bisheriges, einziges Format |
| DMM | 52° 37,205' N | Viele handelsübliche GPS-Geräte |
| DD | 52,62008° N | Einfache Dezimaldarstellung, Online-Kartendienste |
| UTM | 32U 599035 5674453 | Vermessung, topografisches Kartenwerk |

Persistiert wie die übrigen Einstellungen über `AppPreferences` (siehe
Abschnitt 5). Anders als z. B. die Genauigkeitsstufe der
Geschwindigkeitsmessung (wirkt laut Abschnitt 4 erst beim nächsten
Öffnen der Tacho-Seite) wird ein Formatwechsel auf der Kompass-Seite
SOFORT sichtbar - dafür hört `CompassPage` per `ListenableBuilder` direkt
auf `AppPreferences`. Das ist hier unproblematisch (anders als bei der
Genauigkeitsstufe), da sich lediglich die TEXTDARSTELLUNG eines bereits
vorliegenden GPS-Werts ändert, kein Sensor-Stream neu gestartet werden
muss. Dafür bekommt `CompassPage` jetzt (wie `SpeedPage`, `TrackPage`,
`SettingsPage` bereits zuvor) `AppPreferences` als Konstruktor-Parameter
durchgereicht (siehe `HomeShell._buildPage`).

**DMS/DMM/DD - Breite und Länge bleiben JEWEILS in einer eigenen Zeile**
(wie bisher), nur die Formatierung selbst ändert sich
(`util/coordinate_formatter.dart`, `CoordinateFormatter.formatPosition`).

**UTM - Sonderfall EINE gemeinsame Zeile statt zwei:** Breite und Länge
fließen bei UTM gemeinsam in EINE Positionsangabe ein (Zone,
Zonenbuchstabe, Rechtswert, Hochwert) - es gibt fachlich keine getrennte
"Breite"/"Länge" mehr. `CompassPage` behandelt die Zeilenanzahl deshalb
nicht mehr als fest (früher zwei `AutoHyphenatingText`-Widgets), sondern
iteriert über die von `CoordinateFormatter.formatPosition` gelieferte
`List<String>` (ein oder zwei Einträge, je nach Format) - siehe
`_positionLines`, `_buildTextBlock`. Die Genauigkeitszeile darunter
(`_positionAccuracyText`) bleibt davon unberührt, da sie sich auf die
zugrunde liegende GPS-Messung bezieht, nicht auf deren Darstellung.

**UTM-Umrechnung - Implementierungsdetails:** Klassische Transversale-
Merkator-Projektion (WGS84-Ellipsoid) nach den weit verbreiteten, auf
Snyder (1987, "Map Projections - A Working Manual") zurückgehenden
Formeln - direkt in Dart implementiert (`CoordinateFormatter._formatUtm`),
ohne zusätzliche Paketabhängigkeit. Genauigkeit im Bereich weniger
Zentimeter für die hier relevanten mittleren Breiten, mehr als
ausreichend gegenüber der GPS-eigenen Ungenauigkeit von i. d. R. mehreren
Metern (`positionAccuracyMeters`, siehe Abschnitt 10).

**Bewusst NICHT berücksichtigt bei UTM:** die Sonderzonen für Norwegen/
Spitzbergen (dort weichen einzelne UTM-Zonengrenzen von der sonst
regelmäßigen 6°-Einteilung ab) sowie die Polargebiete jenseits von
±80°/84° Breite (dort ist genau genommen das UPS-System gebräuchlich,
nicht UTM) - für den nautischen/Outdoor-Einsatzzweck dieser App an
praktisch jedem anderen Ort der Erde ohne Belang; bei Bedarf jederzeit
nachrüstbar. Außerhalb dieses Bereichs liefert die Zonenbuchstaben-
Ermittlung einen neutralen Platzhalter ("Z") statt abzustürzen.

**Betroffene/neue Dateien:**
- `lib/models/position_display_format.dart` (NEU)
- `lib/services/app_preferences.dart` (neue Einstellung)
- `lib/util/coordinate_formatter.dart` (DMM/DD/UTM ergänzt,
  `formatPosition` als neuer, formatübergreifender Einstiegspunkt)
- `lib/ui/compass_page.dart` (nimmt jetzt `AppPreferences` entgegen,
  `ListenableBuilder` für sofortige Reaktion, dynamische Zeilenanzahl)
- `lib/ui/settings_page.dart` (neue Auswahl-Sektion im Unterreiter
  "Anzeige")
- `lib/ui/home_shell.dart` (reicht `preferences` an `CompassPage` durch)

## 26. "Erweitert"-Tab: Dropdown statt Radio-Buttons

**Motivation:** Genauigkeitsstufe der Geschwindigkeitsmessung (3
Optionen) und Pause-Erinnerung (5 Optionen) zeigten als `RadioListTile`
jede Option samt vollständiger Beschreibung gleichzeitig an - auf dem
"Erweitert"-Tab (siehe Abschnitt 24) beanspruchte das spürbar viel
vertikalen Platz, gerade bei der Pause-Erinnerung mit ihren fünf
Optionen.

**Umsetzung:** Beide Abschnitte (`_buildSpeedAccuracySection`,
`_buildAutoPauseReminderSection` in `lib/ui/settings_page.dart`) nutzen
jetzt `DropdownButtonFormField` statt `RadioGroup`/`RadioListTile`. Nur
die Beschreibung der AKTUELL gewählten Option erscheint als eigener
Text darunter - die Beschreibungen der übrigen, gerade nicht gewählten
Optionen sind erst nach dem Aufklappen des Dropdowns sichtbar (dort
zeigt Flutter aus Platzgründen ohnehin nur die Labels, keine
Beschreibungen). Die einleitende Hinweis-Kachel (Akku-Symbol samt
Erklärtext) bleibt bei der Genauigkeitsstufe unverändert bestehen, da
sie sich auf die Auswahl als Ganzes bezieht, nicht auf eine einzelne
Option.

**BEWUSST NICHT geändert:** Die Positionsformat-Auswahl
(`_buildPositionDisplayFormatSection`, Unterreiter "Anzeige", siehe
Abschnitt 25) bleibt bei `RadioGroup`/`RadioListTile` - hier wurde
gezielt nur der "Erweitert"-Tab angepasst.

**Fehlerkorrektur:** `DropdownButtonFormField` verwendete zunächst den
Parameter `value` - in neueren Flutter-Versionen zugunsten von
`initialValue` deprecated (reine Umbenennung zur Vereinheitlichung mit
anderen Form-Feldern wie `TextFormField`, kein Verhaltensunterschied).
Korrigiert.

**Betroffene Dateien:**
- `lib/ui/settings_page.dart`

## 27. Barometrische Höhe fließt in die Track-Aufzeichnung (und damit in Export/Import) ein

**Ausgangslage:** Die Kompass-Seite nutzt seit Abschnitt 10 bereits die
deutlich präzisere, gegen GPS kalibrierte Barometer-Höhe
(`BarometerAltitudeService`) für ihre Höhenanzeige. `TrackRecordingService`
verwendete für jeden aufgezeichneten `TrackPoint` bislang aber
ausschließlich die (deutlich ungenauere, siehe Abschnitt 10) GPS-
Rohhöhe (`Position.altitude`) - unabhängig davon, ob das Gerät ein
Barometer besitzt.

**Umsetzung:** `TrackRecordingService` hält jetzt eine eigene
`BarometerAltitudeService`-Instanz und kalibriert sie laufend gegen die
eigene, ohnehin für den Trackpunkt selbst verwendete GPS-Position (siehe
`_onPosition`) - ein zusätzlicher, eigener Standort-Stream wie ihn die
Kompass-Seite über `AltitudeService` nutzt, ist dafür NICHT nötig, das
spart zusätzlichen GPS-/Akkuverbrauch. Sobald ein kalibrierter
Barometer-Wert vorliegt, wird er bevorzugt gegenüber der GPS-Rohhöhe für
den `altitudeMeters`-Wert jedes neuen `TrackPoint` verwendet
(`_currentBarometerAltitudeMeters`), andernfalls (Gerät ohne Barometer,
oder direkt nach dem Start noch keine Kalibrierung erfolgt) fällt es auf
die GPS-Rohhöhe zurück - fachlich identisch zur bereits bestehenden
Logik auf der Kompass-Seite.

Das Barometer-Listening läuft - analog zum Beschleunigungssensor für die
Stillstandserkennung (`MotionService`, siehe Abschnitt 6/19) - über die
GESAMTE Aufzeichnung hinweg, auch während einer Pause: Der Sensor selbst
verbraucht (anders als GPS) praktisch keinen nennenswerten zusätzlichen
Akku, und so liegt nach einem Fortsetzen sofort wieder ein aktueller
Wert vor, statt erst auf eine neue Kalibrierung warten zu müssen.

**Export UND Import waren bereits vorbereitet, keine Änderung nötig:**
`TrackPoint.altitudeMeters` ist ein generisches, quellenunabhängiges
Feld - `GpxConverter.encode`/`.decode` (siehe Abschnitt 20) lesen und
schreiben es bereits unverändert als `<ele>`-Element, ohne zwischen GPS-
und Barometer-Herkunft zu unterscheiden (eine GPX-Datei kennt diesen
Unterschied grundsätzlich nicht - `<ele>` ist schlicht "die Höhe an
diesem Punkt"). Die einzige Änderung war deshalb die Quelle, aus der der
Wert beim Aufzeichnen selbst stammt - Export und Import profitieren
automatisch, ohne selbst angefasst werden zu müssen.

**Fehlerkorrektur (im Zuge dieser Änderung entdeckt):** Sowohl die neue
Barometer-Subscription in `TrackRecordingService` als auch die bereits
bestehende auf der Kompass-Seite (`compass_page.dart`) bekamen einen
expliziten `onError`-Handler spendiert. Grund: `BarometerAltitudeService`
reicht Sensor-Fehler (z. B. auf einem Gerät ganz ohne Barometer) bewusst
über den `StreamController` weiter, statt sie selbst zu verschlucken
(anders als z. B. `MotionService`) - ohne einen `onError`-Handler an der
`listen(...)`-Aufrufstelle hätte das einen unbehandelten Stream-Fehler
zur Folge gehabt. In beiden Fällen bedeutet ein Fehler schlicht: es
bleibt bei der GPS-Höhe, kein Absturz.

**Betroffene Dateien:**
- `lib/services/track_recording_service.dart`
- `lib/ui/compass_page.dart` (nur die Fehlerkorrektur, siehe oben)

## 28. Kompassrose vergrößert

**Auf Wunsch angehoben:** Die Stellschrauben aus Abschnitt 10, die die
maximale Größe der Kompassrose begrenzen (`CompassPage._buildBody`/
`build`, `LayoutBuilder`):

| Wert | Vorher | Jetzt |
|---|---|---|
| `maxDialSize` (absolute Obergrenze in logischen Pixeln) | 280 | 360 |
| Anteil der verfügbaren Höhe | 42 % | 48 % |
| Anteil der verfügbaren Breite | 100 % (volle Breite) | 80 % |

`minDialSize` (120) sowie die grundsätzliche Berechnungslogik (`min` aus
einem Anteil der verfügbaren Breite und einem Anteil der verfügbaren
Höhe, per `clamp` auf den Bereich zwischen Minimal- und Maximalwert
begrenzt) bleiben unverändert.

**Neu hinzugekommen - Breitenbegrenzung auf 80 %:** Die Kompassrose
nutzte bislang bei Bedarf die VOLLE verfügbare Breite aus. Jetzt bleibt
zusätzlich links und rechts etwas "Luft" (`maxWidthFraction = 0.8`) -
wirkt dadurch weniger erdrückend/kantenständig, gerade auf schmaleren
Geräten oder im Hochformat mit viel Breite relativ zur Höhe. Die Rose
bleibt dabei automatisch horizontal zentriert (`Align(alignment:
Alignment.topCenter)` um die `SizedBox` mit der berechneten Kantenlänge)
- dafür war keine zusätzliche Anpassung nötig.

**Warum das gefahrlos möglich ist:** Der Textblock darunter (Kurs, Höhe,
Position) ist bereits seit Abschnitt 10 über ein
`FittedBox(fit: BoxFit.scaleDown)` abgesichert - er passt sich
automatisch an den nach Abzug der (jetzt größeren) Kompassrose
verbleibenden Platz an und verkleinert sich bei Bedarf einfach weiter.
Eine Überlappung zwischen Kompassrose und Textblock kann dadurch auf
keiner Bildschirmgröße bzw. Systemschriftgröße entstehen - im
ungünstigsten Fall (kleiner Bildschirm, große Systemschrift) wirkt sich
die Anhebung schlicht kaum aus, da dann ohnehin schon vorher der durch
`availableHeight * 0.48` bestimmte, nicht der feste `maxDialSize`-Wert
die eigentliche Grenze war.

**Betroffene Dateien:**
- `lib/ui/compass_page.dart`

## 29. Track-Seite und Track-Detailansicht: Unterreiter "Karte" und "Details" mit Momentanwerten und Profil-Diagrammen

**Motivation:** Die Karte war bislang der einzige Inhalt sowohl der
laufenden Aufzeichnung (`TrackPage`) als auch der Ansicht eines bereits
gespeicherten Tracks (`TrackDetailPage`). Wichtige Kennzahlen zum
zurückgelegten Höhenverlauf, zur Steigung und zum Geschwindigkeitsverlauf
waren gar nicht einsehbar - weder als aktueller Momentanwert noch als
Verlauf über die gesamte Strecke.

**Umsetzung - zwei neue Unterreiter, analog zur Einstellungsseite (siehe
Abschnitt 24):**

- **`TrackPage`** (laufende Aufzeichnung): "Karte" (bisheriger, alleiniger
  Inhalt) und "Details" (NEU). Die Unterreiter sitzen - wie bei
  `SettingsPage` - im `body` (TrackPage teilt sich die `AppBar` mit den
  übrigen Hauptseiten über `HomeShell`, hat also keine eigene). Die
  Start-/Pause-/Beenden-Steuerung bleibt bewusst AUSSERHALB der
  Unterreiter, unterhalb von beiden gleichermaßen sichtbar - der Nutzer
  soll die Aufzeichnung auch pausieren/beenden können, während er gerade
  die Details betrachtet.
- **`TrackDetailPage`** (gespeicherter Track): ebenfalls "Karte" und
  "Details". Hier sitzt die `TabBar` dagegen direkt in der eigenen
  `AppBar` dieser Seite (`bottom: TabBar(...)`), da `TrackDetailPage`
  (anders als `TrackPage`) eine eigenständige, per `Navigator.push`
  geöffnete Seite mit eigener `AppBar` ist - das ist der dafür
  vorgesehene, idiomatische Flutter-Weg. Enthält KEINEN "Karte"/"Details"-
  Wechsel, wenn der Track gar keine Positionsdaten hat (`_points.isEmpty`)
  - dann wie bisher direkt die Hinweismeldung ohne Tabs.

**Details-Tab von `TrackPage` - Momentanwerte:**

| Wert | Herkunft |
|---|---|
| Geschwindigkeit | `Position.speed` des letzten Punkts (km/h) |
| Kurs | `Position.heading` (Course over Ground aus dem GPS-Signal) |
| Höhenänderung seit Start | aktuelle Höhe minus Höhe des ERSTEN Punkts - kann negativ werden |
| Steigung / Gefälle | siehe unten, `TrackProfileCalculator` |

**WICHTIG - "Kurs" hier ist NICHT derselbe Wert wie auf der
Kompass-Seite:** Die Kompass-Seite zeigt den Magnetkompass-Kurs
(`CompassService`, Magnetometer, siehe README-Antwort zur entsprechenden
Nutzerfrage sowie Abschnitt 10). Der "Kurs" auf dem Track-Details-Tab ist
dagegen der GPS-seitige "Course over Ground" (`Position.heading`,
tatsächliche Bewegungsrichtung über Grund) - inhaltlich der für eine
Streckenaufzeichnung sinnvollere Wert (entspricht bei Bewegung i. d. R.
näherungsweise dem Magnetkompass-Kurs, bei Stillstand oder Rückwärts-/
Seitwärtsbewegung aber nicht zwingend). Bewusst KEINE zusätzliche
`CompassService`-Instanz auf der Track-Seite, um nicht unnötig einen
weiteren Sensor zu belegen - der Wert fällt beim ohnehin laufenden
GPS-Stream mit an.

**Details-Tab von `TrackDetailPage`:** AUSSCHLIESSLICH die vier
Profil-Diagramme, bewusst OHNE Momentanwerte-Karte - ein bereits
abgeschlossener Track hat kein sinnvolles "jetzt" mehr.

**Die vier Profil-Diagramme (beide Seiten, `widgets/track_profile_charts.dart`):**

1. Geschwindigkeitsprofil (km/h)
2. Höhenprofil (m ü. NN, absolute Höhe)
3. Anstiegsprofil - Höhenänderung seit Start (m, kann negativ werden)
4. Steigung/Gefälle (%, kann negativ werden)

Diagramme 3 und 4 entsprechen inhaltlich exakt den beiden letzten
Momentanwerten von `TrackPage` (Höhenänderung, Steigung/Gefälle), nur
als Verlauf über die gesamte bisherige/komplette Strecke statt als
Einzelwert "jetzt".

**Gemeinsame x-Achse - Distanz statt Zeit:** Alle vier Diagramme nutzen
die seit dem ersten Punkt zurückgelegte Strecke (km) als x-Achse, nicht
die verstrichene Zeit - anschaulicher für Höhen-/Steigungsprofile und
näher an der Darstellung, wie sie von Wander-/Radkarten bekannt ist. Bei
längeren Pausen "steht" die Kurve dadurch praktisch still, statt einen
langen flachen Abschnitt zu erzeugen, wie es bei einer Zeit-x-Achse der
Fall wäre.

**Neues Datenfeld `TrackPoint.speedMetersPerSecond`:** Damit auch für
BEREITS GESPEICHERTE Tracks ein echtes (statt nur aus Distanz/Zeit
geschätztes) Geschwindigkeitsprofil möglich ist, speichert
`TrackRecordingService` jetzt zusätzlich die vom Gerät gemessene
Momentan-Geschwindigkeit (`Position.speed`) in jedem `TrackPoint` (JSON-
Feld `spd`). Rückwärtskompatibel: `TrackPoint.fromJson` liefert für
VOR dieser Änderung gespeicherte Dateien einfach `null` (Feld fehlt
dort), `GpxConverter.decode` setzt es für importierte GPX-Tracks
grundsätzlich auf `null` (GPX kennt kein Standardfeld für die
Geschwindigkeit, siehe Abschnitt 20) - `TrackProfileCalculator` schätzt
in beiden Fällen ersatzweise aus Distanz/Zeit zum vorherigen Punkt.

**`util/track_profile_calculator.dart` (NEU):** Reine, zustandslose
Umwandlungslogik (analog zu `GpxConverter`/`CoordinateFormatter`) - macht
aus einer `List<TrackPoint>` eine `List<TrackProfilePoint>` mit
kumulierter Distanz, (ggf. geschätzter) Geschwindigkeit,
Höhenänderung seit Start und Steigung/Gefälle. Die Steigungsberechnung
verwendet dabei bewusst NICHT zwingend den unmittelbar vorherigen Punkt,
sondern sucht rückwärts nach dem letzten Punkt, der mindestens 5 m
entfernt liegt (`_minGradientSegmentMeters`) - bei sehr eng
beieinanderliegenden Punkten würde sonst schon eine kleine
Höhen-Messungenauigkeit (auch mit der präziseren Barometer-Höhe aus
Abschnitt 27 nie exakt Null) durch den kleinen Nenner zu unrealistisch
großen Prozentwerten hochgerechnet. Zusätzlich werden Prozentwerte auf
±40 % gedeckelt (`_maxAbsGradientPercent`), damit ein einzelner
Messausreißer nicht die gesamte Diagramm-Skala verzerrt.

**`ui/widgets/profile_chart.dart` (NEU) - eigenes Diagramm-Widget statt
Paketabhängigkeit:** Ein einfaches, selbst gezeichnetes
(`CustomPainter`) Liniendiagramm mit gefüllter Fläche unter der Kurve,
y-Achsen-Beschriftung (Minimum/Mitte/Maximum) und x-Achsen-Beschriftung
(Distanz-Spanne) - bewusst KEIN zusätzliches Chart-Paket als
Abhängigkeit, sondern passend zum bisherigen Stil dieses Projekts
(vollständig selbst gezeichnete, großformatige Anzeigen, siehe
`CompassDial`, `SevenSegmentDisplay`) umgesetzt. Diagramme mit
möglicherweise negativen Werten (Anstieg, Steigung/Gefälle) erhalten
zusätzlich eine hervorgehobene Null-Linie (`showZeroLine`), damit auf
einen Blick sichtbar ist, ob gerade auf- oder abwärts geht.

**`ui/widgets/track_profile_charts.dart` (NEU):** Bündelt die vier
`ProfileChart`-Instanzen zu einer gemeinsamen Spalte - von BEIDEN Seiten
verwendet (`TrackPage` und `TrackDetailPage`). Nimmt bewusst bereits
BERECHNETE `TrackProfilePoint`s entgegen statt selbst
`TrackProfileCalculator.compute` aufzurufen: Auf `TrackPage` werden
dieselben Werte zusätzlich für die Momentanwerte-Karte benötigt, die
Berechnung soll pro Rebuild nur einmal erfolgen.

**Scrollverhalten:** Beide Details-Tabs sind in ein
`SingleChildScrollView` eingebettet - Momentanwerte-Karte (nur
`TrackPage`) plus vier Diagramme finden auf den meisten Bildschirmen
nicht komplett ohne Scrollen Platz.

**Bewusst nicht optimiert - Neuberechnung bei jedem Rebuild:** Auf
`TrackPage` wird `TrackProfileCalculator.compute` bei JEDEM Rebuild des
Details-Tabs neu ausgeführt (ausgelöst durch den ohnehin schon
laufenden 1-Sekunden-Ticker bzw. jeden neuen Punkt, siehe Abschnitt 16/19)
- für die bei einer typischen Aufzeichnung zu erwartende Punktezahl
(einige Hundert bis wenige Tausend) unproblematisch schnell, bei sehr
langen Mehrstunden-Aufzeichnungen ließe sich das bei Bedarf noch auf eine
inkrementelle Berechnung umstellen (bislang nicht nötig).

**Betroffene/neue Dateien:**
- `lib/models/track_point.dart` (neues Feld `speedMetersPerSecond`)
- `lib/util/gpx_converter.dart` (setzt das neue Feld beim Import auf
  `null`)
- `lib/services/track_recording_service.dart` (erfasst Geschwindigkeit
  und Kurs)
- `lib/util/track_profile_calculator.dart` (NEU)
- `lib/ui/widgets/profile_chart.dart` (NEU)
- `lib/ui/widgets/track_profile_charts.dart` (NEU)
- `lib/ui/track_page.dart` (Unterreiter, Momentanwerte-Karte)
- `lib/ui/track_detail_page.dart` (Unterreiter)

**Fehlerkorrektur:** `package:intl` bringt eine eigene `TextDirection`-
Klasse mit (für bidirektionalen Text, LTR/RTL/UNKNOWN, Teil der
Bidi-Unterstützung von intl) - kollidiert mit Flutters eigenem
`TextDirection` (aus `dart:ui`, re-exportiert über `material.dart`),
sobald beide Pakete gemeinsam importiert UND `TextDirection` tatsächlich
verwendet wird (hier: `TextPainter` in `profile_chart.dart`). Fehlerbild:
"The argument type 'TextDirection' can't be assigned to the parameter
type 'TextDirection?'" - der Compiler zog das falsche der beiden
gleichnamigen `TextDirection` heran. Behoben durch
`import 'package:intl/intl.dart' hide TextDirection;` in
`profile_chart.dart` (das intl-eigene `TextDirection` wird dort ohnehin
nicht benötigt).

## 30. Mehrere Fehlerkorrekturen nach ausführlichem Praxistest

Sammelt vier voneinander unabhängige Korrekturen, die sich bei
intensivem Testen auf dem S23 Ultra gezeigt haben.

### 30.1 Y-Achsen-Beschriftung der Profil-Diagramme unlesbar

**Fehler:** In `ProfileChart._drawGridAndLabels` lag der Ankerpunkt der
rechtsbündigen y-Achsen-Beschriftung bei x=0. Da bei rechtsbündigem Text
die Textbreite VOM Anker ABGEZOGEN wird, um die linke Startposition zu
erhalten, landete diese bei x=0 minus Textbreite - also im Negativen und
damit außerhalb der sichtbaren Zeichenfläche.

**Korrektur:** Ankerpunkt auf `_yAxisLabelWidth - 6` (den rechten Rand
des dafür vorgesehenen Beschriftungsbereichs, direkt vor dem eigentlichen
Diagrammbereich) korrigiert.

### 30.2 Steigungswerte fluktuierten unrealistisch stark (±5 % auf ebener Strecke)

**Ursache gefunden:** `BarometerAltitudeService.calibrate()` wurde bei
JEDER einzelnen GPS-Messung aufgerufen (siehe `TrackRecordingService._onPosition`,
Abschnitt 27) - und setzte dabei jedes Mal die komplette Höhen-/
Druck-Referenz neu, nicht nur die Position. Der eigentliche Zweck des
Barometers - eine feine, praktisch rauschfreie RELATIVE Höhenänderung
gegenüber einem Referenzpunkt zu liefern (siehe Abschnitt 10) - wurde
dadurch bei jeder Neukalibrierung wieder auf die selbst deutlich
ungenauere GPS-Höhe "zurückgesetzt", noch bevor sich die Glättung
überhaupt bemerkbar machen konnte. Bei einem `TrackProfileCalculator`-
Mindestabstand von bis dahin nur 5 m zwischen den Vergleichspunkten
reichten schon 10-20 cm GPS-Höhenrauschen für mehrere Prozent Ausschlag.

**Zwei Korrekturen (siehe dortige Kommentare für Details):**

1. `BarometerAltitudeService.calibrate()`: Die eigentliche Höhen-/
   Druck-Referenz wird jetzt höchstens einmal pro Minute
   (`_minRecalibrationInterval`) tatsächlich übernommen - wetterbedingte
   Luftdruckänderungen sind über eine Minute ohnehin vernachlässigbar
   gering, die Barometer-Glättung kommt so tatsächlich zum Tragen.
   Position (Breite/Länge/Genauigkeit) ist von dieser Drosselung bewusst
   AUSGENOMMEN und bleibt weiterhin bei jedem Aufruf aktuell (wichtig für
   die Positionsanzeige auf der Kompass-Seite, Abschnitt 25).
2. `TrackProfileCalculator._minGradientSegmentMeters`: von 5 m auf 20 m
   angehoben - als zweite, ergänzende Schutzschicht.

### 30.3 Momentanwerte-Karte: volle Breite und größere Schrift

**Vorher:** `Wrap` mit vier `SizedBox(width: 150)`-Einträgen - nutzte
die verfügbare Kartenbreite nicht aus, Werte in `titleMedium`.

**Jetzt:** 2×2-Raster aus zwei `Row`s mit je zwei `Expanded`-Zellen
(nutzt die volle verfügbare Breite gleichmäßig), Wertgröße auf
`headlineSmall` angehoben - analog zur bereits bestehenden Vergrößerung
der Info-Zeilen auf der Tacho-Seite (siehe Abschnitt 11,
`_readableInfoStyle`).

### 30.4 Verlorene Aufzeichnungen bei längerem Hintergrundbetrieb bzw. nach Wischen

Das gravierendste der gemeldeten Probleme - dazu vorab **ehrlich**: Ich
kann die genaue Ursache ohne Zugriff auf dein Gerät (insbesondere ein
`adb logcat`-Mitschnitt während des Auftretens) nicht mit letzter
Sicherheit bestimmen. Recherche zu bekannten geolocator-Eigenheiten
förderte aber zwei sehr plausibel passende Fundstellen zutage:

- Ein Pull Request im geolocator-Projekt ("Android location stream not
  cancelling", #1153) beschreibt einen Fehler beim Zusammenspiel des
  nativen Standort-Service mit MEHREREN verbundenen FlutterEngines bzw.
  einer Unterscheidung zwischen "Stream explizit vom Nutzer beendet" und
  "Activity-Prozess wird zerstört" - beides trifft auf unsere in
  Abschnitt 21 bewusst eingeführte persistente FlutterEngine-Architektur
  zu, die von den sonst üblichen Annahmen (eine Engine pro Activity-
  Lebenszyklus) abweicht.
- Ein bekannter geolocator-Fehlerbericht (#1178) zeigt eine
  `PlatformException` ("Service.startForeground() not allowed") beim
  Neustart des Standort-Service aus dem Hintergrund heraus - eine seit
  Android 12 bestehende Einschränkung.

**Was in jedem Fall ein echter, unabhängig vom genauen Auslöser
vorhandener Bug war:** Der Positions-Stream in `TrackRecordingService`
hatte BISHER GAR KEINE Fehlerbehandlung (`_startListening` endete
einfach mit `.listen(_onPosition)`, ohne `onError`/`onDone`). Ein Fehler
wie die oben genannte `PlatformException` wäre dadurch schlicht
STILLSCHWEIGEND verschluckt worden - keine weiteren Punkte mehr, ohne
dass die App davon irgendetwas gemerkt hätte. Das ist jetzt behoben:

**Korrektur 1 - automatischer Neustart-Versuch bei Fehlern:**
`_startListening` behandelt `onError` UND `onDone` jetzt aktiv
(`cancelOnError: false`, damit ein Fehler nicht automatisch das Ende der
Subscription bedeutet) und versucht bei einem Fehler bzw. einem
unerwarteten Stream-Ende automatisch einen Neustart - mit exponentiell
steigender Wartezeit zwischen den Versuchen (2/4/8/16/30 Sekunden,
`_retryDelaysSeconds`), um kein Totlaufen bei dauerhaft bestehenden
Problemen (z. B. entzogene Berechtigung) zu riskieren. Ein erfolgreich
empfangener Punkt setzt den Fehlerzähler zurück.

**Korrektur 2 - Checkpoint-Sicherung als Sicherheitsnetz gegen den
Extremfall (Prozess stirbt trotzdem):** Selbst mit robusterer
Fehlerbehandlung bleibt ein Restrisiko, dass der komplette App-Prozess
aus einem der oben genannten (oder einem noch unbekannten) Grund
tatsächlich beendet wird - in diesem Fall würde Korrektur 1 nicht mehr
greifen können, da mit dem Prozess auch der komplette Dart-Zustand
verloren geht. Deshalb schreibt `TrackRecordingService` die bisher
gesammelten Punkte jetzt zusätzlich periodisch (höchstens alle 15
Sekunden, `_minCheckpointInterval`) als Checkpoint-Datei
(`ontour_recording_checkpoint.json`, bewusst AUSSERHALB des
`tracks/`-Verzeichnisses von `TrackStorageService`, damit sie nie
versehentlich in der Liste gespeicherter Tracks auftaucht) in das
app-eigene Dokumentenverzeichnis. Diese Datei wird bei jedem REGULÄREN
Beenden (`stop`/`discard`) automatisch wieder gelöscht.

Findet `TrackPage` beim Öffnen (nur relevant, solange `state` noch
`idle` ist) eine solche Checkpoint-Datei vor, bedeutet das: Die letzte
Aufzeichnung wurde nicht regulär beendet - ein Dialog bietet an, sie als
Track zu speichern ("Wiederhergestellte Aufzeichnung vom ...") oder zu
verwerfen. Die Distanz wird dabei aus den geretteten Punkten neu
berechnet; eine pausenbereinigte Dauer wie bei einer regulär beendeten
Aufzeichnung gibt es naturgemäß nicht mehr (die Dauer entspricht der
Differenz zwischen erstem und letztem Zeitstempel).

**Was ich zusätzlich empfehle, falls das Problem weiterhin auftritt:**
1. `flutter pub outdated` ausführen und `geolocator`/`geolocator_android`
   auf die neueste Version bringen - falls die oben verlinkte
   Fehlerkorrektur #1153 in deiner aktuell installierten Version noch
   nicht enthalten ist, könnte ein Update allein schon helfen.
2. Falls es erneut auftritt: `adb logcat` während bzw. kurz nach dem
   Auftreten mitschneiden (idealerweise gefiltert auf `flutter` und
   `AndroidRuntime`) - ein tatsächlicher nativer Absturz würde sich dort
   als Stacktrace zeigen und die genaue Ursache eindeutig bestätigen,
   was mir eine gezieltere Korrektur ermöglichen würde.

**Betroffene Dateien:**
- `lib/ui/widgets/profile_chart.dart` (30.1)
- `lib/services/barometer_altitude_service.dart` (30.2)
- `lib/util/track_profile_calculator.dart` (30.2)
- `lib/ui/track_page.dart` (30.3, 30.4)
- `lib/services/track_recording_service.dart` (30.4)

## 31. Diagnose-Protokoll (Logcat) exportierbar - nur in Debug-/Test-Builds

**Hintergrund:** Zur weiteren Fehlersuche bei dem in Abschnitt 30.4
beschriebenen, noch nicht abschließend geklärten Problem (verlorene
Aufzeichnungen) wird jetzt fortlaufend ein technisches Diagnose-Protokoll
mitgeschrieben, das sich direkt vom Gerät aus exportieren und
weitergeben lässt - ohne dafür einen Rechner mit `adb` zur Hand haben zu
müssen (relevant, da das beschriebene Problem typischerweise unterwegs,
nicht am Schreibtisch auftritt).

**Native Umsetzung (`OnTourApplication.kt`, `startLogcatCapture`):**
Startet `logcat -v threadtime` als Kindprozess und schreibt dessen
Ausgabe fortlaufend in eine Datei im app-eigenen internen Speicher
(`ontour_diagnose.log`). Apps dürfen seit Android 4.1 ohne besondere
Berechtigung ihre EIGENEN Logcat-Zeilen lesen (nur das Mitlesen fremder
Apps ist gesperrt) - für die Diagnose eines Fehlers innerhalb des
eigenen Prozesses genau richtig, ohne zusätzliche Berechtigung in der
`AndroidManifest.xml`. Die Datei wird bei jedem Prozessstart neu
begonnen und bei Überschreiten von 5 MB verworfen und neu begonnen
(verhindert unbegrenztes Wachstum bei sehr langen Testsitzungen, z. B.
mehrstündigen Wanderungen).

**WICHTIG - NUR in Debug-/Test-Builds aktiv:** Die Aufzeichnung startet
ausschließlich, wenn das von Android selbst gesetzte "debuggable"-Flag
der APK aktiv ist (`ApplicationInfo.FLAG_DEBUGGABLE`, wahr für
`flutter run`/eine Debug-APK, falsch für einen signierten Release-Build)
- in einem für den Play Store bestimmten Release-Build läuft sie
automatisch NICHT, ohne dass dafür manuell etwas umgestellt werden
müsste. Grund: Die Log-Zeilen enthalten zwangsläufig auch GPS-Positionen
und andere technische Daten - eine dauerhaft aktive Protokollierung
wäre für echte Nutzer weder nötig noch angemessen.

**Fehlerkorrektur:** Ursprünglich stattdessen per `BuildConfig.DEBUG`
geprüft - das erfordert aber `buildFeatures { buildConfig = true }` in
der app-eigenen `build.gradle`, was seit neueren Android-Gradle-Plugin-
Versionen nicht mehr automatisch aktiviert ist und ohne diese
zusätzliche, manuelle Gradle-Anpassung zu einem Kompilierfehler
("Unresolved reference 'BuildConfig'") führte. `ApplicationInfo.FLAG_DEBUGGABLE`
liefert dasselbe Ergebnis, ganz ohne zusätzliche Gradle-Konfiguration.

**Export (`lib/services/diagnostic_log_service.dart`, NEU):** Kotlins
`filesDir` entspricht unter Android exakt dem, was Flutters
`getApplicationDocumentsDirectory()` liefert - beide Seiten berechnen
unabhängig voneinander denselben Dateipfad, ein zusätzlicher
MethodChannel dafür ist nicht nötig. Auf der Info-Seite (`info_page.dart`)
erscheint - NUR sichtbar, wenn tatsächlich eine nicht-leere Log-Datei
existiert (praktisch also nur in Debug-Builds) - ein Button "Diagnose-
Protokoll exportieren", der die Datei über den nativen "Teilen"-Dialog
anbietet (`share_plus`, analog zum bestehenden GPX-Export, siehe
Abschnitt 20), inklusive eines kurzen Datenschutzhinweises direkt über
dem Button.

**Betroffene/neue Dateien:**
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt`
  (`startLogcatCapture`)
- `lib/services/diagnostic_log_service.dart` (NEU)
- `lib/ui/info_page.dart` (Export-Button samt Hinweistext)

## 32. KRITISCHE Fehlerkorrektur: App-Absturz beim Start auf echtem Gerät (Logcat-Aufzeichnung)

**Symptom:** Nach Installation eines Debug-Builds mit der in Abschnitt
31 beschriebenen Logcat-Aufzeichnung auf einem echten Gerät (Samsung
S23 Ultra) ließ sich die App überhaupt nicht mehr öffnen - sie stürzte
unmittelbar beim Start ab (im Emulator dagegen unauffällig).

**Ursache:** In `OnTourApplication.startLogcatCapture()` liefen das
Löschen der alten Log-Datei UND der eigentliche
`ProcessBuilder("logcat", ...).start()`-Aufruf noch SYNCHRON auf dem
aufrufenden Thread - der bei einem Aufruf aus `onCreate()` heraus der
HAUPT-THREAD ist, und das ganz am Anfang des App-Starts, noch bevor
Flutter/die UI überhaupt initialisiert sind. Ein echtes Gerät setzt
SELinux-Beschränkungen für Apps deutlich strenger durch als der
Emulator - das Starten eines Systemprogramms wie `logcat` direkt aus der
App heraus wurde dort offenbar nicht sauber mit einer regulären, vom
umgebenden `try/catch` auffangbaren Exception quittiert, sondern führte
zu einem Absturz des gesamten Prozesses, noch bevor überhaupt etwas
sichtbar wurde - für den Nutzer nicht von einem regulären App-Absturz zu
unterscheiden.

**Korrektur:** Ausnahmslos ALLES (Datei-Löschung, Prozessstart,
Lese-Schleife) läuft jetzt in einem eigenen Hintergrund-Thread, der als
Allererstes gestartet wird - der Haupt-Thread bzw. der App-Start selbst
führt dadurch überhaupt keinen mit `logcat` zusammenhängenden Code mehr
synchron aus. Zusätzlich wird jetzt `Throwable` statt nur `Exception`
abgefangen, um auch Fehlerarten abzudecken, die kein regulärer
`Exception`-Typ sind.

**Falls der Absturz dennoch weiterhin auftritt:** Das würde bedeuten,
dass die eigentliche Ursache doch nicht (nur) bei der Logcat-
Aufzeichnung liegt - dann sollte die Funktion versuchsweise komplett
deaktiviert werden (Aufruf von `startLogcatCapture()` in `onCreate()`
auskommentieren), um App-Start und Diagnose-Funktion vollständig
voneinander zu entkoppeln. Ein `adb logcat`-Mitschnitt von einem PC aus
(sofern verfügbar) würde in diesem Fall - ironischerweise - die
zuverlässigste Diagnosemethode bleiben, da er unabhängig davon
funktioniert, ob die App selbst überhaupt startet.

**Betroffene Dateien:**
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt`

## 33. Logcat-Aufzeichnung vollständig verworfen

**Bestätigt:** Auch nach der in Abschnitt 32 beschriebenen Korrektur
(alles in einen Hintergrund-Thread verlagert, `Throwable` statt nur
`Exception` abgefangen) trat exakt derselbe sofortige Absturz beim
App-Start auf dem Samsung S23 Ultra weiterhin auf. Das zeigt: Nicht die
Threading-Situation war das eigentliche Problem, sondern der bloße
VERSUCH, `logcat` als Kindprozess zu starten, führt auf diesem Gerät zu
einem Fehler, der unterhalb der Java-Exception-Ebene liegt und sich
grundsätzlich nicht per `try`/`catch` abfangen lässt (vermutlich eine
harte SELinux-Verweigerung, die den Prozess direkt beendet, statt dem
aufrufenden Code eine reguläre Fehlerauskunft zu liefern).

**Konsequenz:** Der komplette, auf einem nativen `logcat`-Kindprozess
basierende Ansatz aus Abschnitt 31/32 wurde ERSATZLOS aus
`OnTourApplication.kt` entfernt (Methode `startLogcatCapture`, die
zugehörigen Konstanten sowie der Aufruf in `onCreate`). Priorität hat
eindeutig eine funktionierende App gegenüber einer Diagnose-Funktion,
egal wie nützlich Letztere gewesen wäre.

**Betroffene Dateien:**
- `native_android/de/clausjbauer/ontour/OnTourApplication.kt`

## 34. Neuer, sicherer Ersatz: rein Dart-seitiges Diagnose-Protokoll

**Ersetzt Abschnitt 31 vollständig.** Statt Logcat-Ausgaben über einen
nativen Kindprozess mitzuschneiden, protokolliert die App jetzt gezielt
selbst die für die Fehlersuche (Abschnitt 30.4) relevanten Ereignisse -
über ganz normale Dart-Datei-Schreibvorgänge (`dart:io`), OHNE jeden
nativen Prozessaufruf und damit ohne das in Abschnitt 33 beschriebene
Risiko.

**`lib/services/diagnostic_log_service.dart` (NEU, ersetzt die
gleichnamige Datei aus Abschnitt 31):** Einfaches Singleton
(`DiagnosticLogService.instance`) mit einer `log(String message)`-
Methode, die Zeitstempel plus Text an eine Textdatei
(`ontour_diagnose.log`, wie zuvor im app-eigenen Dokumentenverzeichnis)
anhängt - bei jedem App-(Prozess-)Start neu begonnen, ab 2 MB verworfen
und neu begonnen. Bewusst "fire and forget" (nie awaited): Ein
Fehlschlag beim Schreiben darf niemals die eigentliche Funktion der App
beeinträchtigen.

**EINSCHRÄNKUNG (bewusst in Kauf genommen):** Ein ECHTER nativer Absturz
(z. B. ein Kotlin-seitiger Fehler innerhalb des geolocator-Plugins)
würde WEITERHIN nicht hier erfasst, da der Dart-Isolate in diesem Fall
selbst nicht mehr weiterläuft, um den Absturz noch protokollieren zu
können - dafür bliebe weiterhin nur ein per PC angeschlossenes
`adb logcat`. Erfasst werden aber alle Dart-seitig sichtbaren
Ereignisse - das deckt den WAHRSCHEINLICHEREN Fall aus Abschnitt 30.4
(Aufzeichnung "friert" unbemerkt ein, OHNE dass die App komplett
abstürzt) bereits gut ab, und liefert im Fall eines echten Absturzes
zumindest die letzten Ereignisse VOR dem Absturz (z. B. ob kurz zuvor
noch ein Checkpoint erfolgreich gesichert wurde).

**Protokollierte Ereignisse:**

| Ereignis | Wo |
|---|---|
| Aufzeichnung gestartet | `TrackRecordingService.start` |
| Pausiert (automatisch/manuell), Punktezahl | `_pauseInternal` |
| Fortgesetzt (automatisch/manuell) | `resume` |
| Beendet (Name, Punktezahl, Distanz) | `stop` |
| Verworfen (Punktezahl) | `discard` |
| Stream-Fehler samt Neustart-Versuch (siehe Abschnitt 30.4) | `_handleStreamError` |
| Checkpoint gesichert (Punktezahl) - "Herzschlag"-Nachweis | `_maybeSaveCheckpoint` |
| App-Lebenszyklus-Wechsel (nur während einer laufenden Aufzeichnung) | `HomeShell.didChangeAppLifecycleState` |
| App-Prozess gestartet | `HomeShell.initState` |

Der letzte Eintrag ist besonders aufschlussreich für die Fehlersuche:
`HomeShell.initState` läuft dank der persistenten FlutterEngine
(Abschnitt 21) NUR EINMAL pro tatsächlichem Android-Prozess, nicht bei
jedem Wiederöffnen nach einem Wischen. Taucht dieser Eintrag im
Protokoll ÖFTER auf, als aufgrund der tatsächlichen Nutzung zu erwarten
wäre, ist das ein direkter Beleg dafür, dass der Prozess zwischenzeitlich
tatsächlich neu gestartet wurde - genau die Frage, die in Abschnitt 30.4
noch offen war.

**Fehlerkorrektur:** `info_page.dart` erzeugte zunächst noch per
`DiagnosticLogService()` eine eigene Instanz - seit der Umstellung auf
ein Singleton (`DiagnosticLogService.instance`, siehe oben) hat die
Klasse aber nur noch einen privaten Konstruktor, was zu einem
Kompilierfehler führte ("doesn't have an unnamed constructor"). Auf
`DiagnosticLogService.instance` korrigiert.

**Export:** Unverändert über die Info-Seite (`info_page.dart`,
"Diagnose-Protokoll exportieren", nur sichtbar bei vorhandener,
nicht-leerer Datei) - die API von `DiagnosticLogService` (`hasLog()`,
`shareLog()`) blieb bewusst identisch zur vorherigen, verworfenen
Fassung, `info_page.dart` musste dafür inhaltlich nicht geändert werden.

**Betroffene/neue Dateien:**
- `lib/services/diagnostic_log_service.dart` (NEU, ersetzt Abschnitt 31)
- `lib/services/track_recording_service.dart` (Log-Aufrufe an den
  genannten Stellen)
- `lib/ui/home_shell.dart` (Log-Aufrufe für App-Start und
  Lebenszyklus-Wechsel)

## 35. Diagnose-Protokoll auf Nicht-Release-Builds beschränkt

**Lücke entdeckt bei der Frage, ob Build 28 auch über einen internen
Play-Store-Test funktioniert:** Beim vollständigen Entfernen der
nativen Logcat-Variante (Abschnitt 33) und der Umstellung auf den rein
Dart-seitigen Logger (Abschnitt 34) wurde die ursprünglich für die
native Variante vorgesehene Beschränkung auf Test-Builds NICHT auf den
neuen Ersatz übertragen - `DiagnosticLogService.log()` hätte dadurch
auch in einem für den Play Store bestimmten Release-Build (ein interner
Test lädt technisch einen ganz normalen, signierten Release-Build hoch)
bei jedem echten Nutzer unbemerkt mitgeschrieben.

**Korrektur:** `log()`, `hasLog()` und (zur zusätzlichen Absicherung)
auch `shareLog()` brechen jetzt sofort ab, wenn `kReleaseMode` (aus
`package:flutter/foundation.dart`) wahr ist - eine von Flutter selbst
zur Kompilierzeit gesetzte Konstante, die für `flutter build
appbundle`/`flutter build apk --release` `true` ergibt, für `flutter
run` sowie Debug-/Profile-Builds `false`. Damit ist die ursprünglich
verfolgte Absicht (Diagnose ausschließlich in Test-Builds) wieder
hergestellt - diesmal rein Dart-seitig, ganz ohne Gradle-Konfiguration
oder native Beteiligung.

**Betroffene Dateien:**
- `lib/services/diagnostic_log_service.dart`

## 36. Fehlende Benachrichtigungs-Berechtigung: kein sichtbarer Hintergrund-Task

**Beobachtung nach dem Neuaufsetzen (Deinstallation der Play-Store-
Version, Installation eines frischen Debug-Builds):** Eine Aufzeichnung
ließ sich zwar starten, aber es erschien zu keinem Zeitpunkt ein
sichtbarer Hintergrund-Task (die vom Foreground-Service erwartete
Benachrichtigung "onTour zeichnet auf", siehe Abschnitt 19) - UND das
Diagnose-Protokoll (Abschnitt 34) enthielt nicht einmal den allerersten,
eigentlich unbedingt geschriebenen Eintrag "Aufzeichnung gestartet".

**Ursache:** Die App fragte bislang AUSSCHLIESSLICH die Standort-
Berechtigung aktiv zur Laufzeit ab (`Geolocator.requestPermission()`,
siehe Abschnitt 2). `POST_NOTIFICATIONS` (ab Android 13/API 33 eine
gewöhnliche Laufzeit-Berechtigung wie jede andere) war zwar bereits seit
Abschnitt 2 in der `AndroidManifest.xml` EINGETRAGEN - das allein reicht
seit Android 13 aber nicht mehr aus, um Benachrichtigungen tatsächlich
anzeigen zu dürfen; es braucht zusätzlich eine explizite
Laufzeit-Abfrage, die bislang fehlte. Nach einer Neuinstallation
(Berechtigungen werden dabei vollständig zurückgesetzt) war
`POST_NOTIFICATIONS` deshalb nicht erteilt.

Das erklärt BEIDE Beobachtungen zusammen: Ohne die Berechtigung kann
`geolocator` keine sichtbare Foreground-Service-Benachrichtigung zeigen
- UND das Fehlen führte vermutlich sogar zu einem SYNCHRONEN Fehler
direkt beim Aufruf von `Geolocator.getPositionStream(...)` mit gesetztem
`foregroundNotificationConfig`. Da `TrackRecordingService.start()`
bislang KEIN eigenes `try`/`catch` um `_startListening()` hatte (im
Unterschied zu den bereits in Abschnitt 30.4 behandelten ASYNCHRONEN
Stream-Fehlern, die über `onError` abgefangen werden), verhinderte ein
solcher synchroner Fehler auch den danach folgenden, eigentlich
unbedingten Diagnose-Log-Eintrag - der Zustand (`state`) blieb dabei
äußerlich auf `recording` stehen, obwohl nie ein einziger GPS-Punkt
einging.

**Zwei Korrekturen:**

1. **Neue Abhängigkeit `permission_handler`** (`^12.0.1`) - fragt
   `Permission.notification` jetzt aktiv beim Öffnen der Track-Seite ab
   (`TrackPage._initialize`, direkt im Anschluss an die bereits
   bestehende Standort-Berechtigungsprüfung), noch bevor der Nutzer
   überhaupt auf "Aufzeichnung starten" tippt - beide
   Berechtigungsdialoge (Standort, Benachrichtigung) erscheinen dadurch
   im selben Arbeitsschritt, statt den Nutzer beim eigentlichen Start
   zusätzlich zu unterbrechen. Ein Ablehnen wird bewusst NICHT
   blockierend behandelt (kein eigener Hinweisbildschirm wie bei der
   Standort-Berechtigung) - die Aufzeichnung funktioniert technisch auch
   ohne sichtbare Benachrichtigung weiter, nur eben ohne die in
   Abschnitt 19 beschriebenen Vorteile für den Hintergrundbetrieb.
   `permission_handler` wurde bewusst einer selbst gebauten,
   MethodChannel-basierten Lösung vorgezogen - das Paket übernimmt
   korrekt die Zuordnung zur jeweils AKTUELLEN Activity trotz der
   persistenten FlutterEngine (Abschnitt 21), was ein selbst gebauter
   Ansatz deutlich fehleranfälliger gemacht hätte.
2. **`TrackRecordingService.start()`:** Der Diagnose-Log-Eintrag
   "Aufzeichnung gestartet" steht jetzt GANZ AM ANFANG der Methode
   (statt erst nach `_startListening()`) und `_startListening()` selbst
   ist jetzt zusätzlich gegen SYNCHRONE Fehler abgesichert (`try`/
   `catch`, der Fehler wird dabei an dieselbe Logik wie asynchrone
   Stream-Fehler übergeben, siehe `_handleStreamError`/Abschnitt 30.4) -
   ein Fehler beim Start kann dadurch nie wieder unbemerkt den
   Diagnose-Log-Eintrag verhindern, UND ein automatischer Neustart-
   Versuch greift jetzt auch für diesen Fehlerfall.

**Falls `compileSdkVersion` beim Bauen bemängelt wird:** `permission_handler`
12.x setzt `compileSdkVersion 35` voraus - falls Gradle deswegen einen
Fehler meldet, in `android/app/build.gradle` (bzw. `build.gradle.kts`)
`compileSdk`/`compileSdkVersion` entsprechend auf mindestens 35 anheben.

**Betroffene Dateien:**
- `pubspec.yaml` (neue Abhängigkeit `permission_handler`)
- `lib/ui/track_page.dart` (Berechtigungsabfrage)
- `lib/services/track_recording_service.dart` (Log-Reihenfolge,
  Absicherung gegen synchrone Fehler)

## 37. Genauigkeits-Anzeige und Mess-Impuls auf Tacho-, Kompass- und Track-Seite

**Umsetzung (auf Wunsch):** Zwei neue, wiederverwendbare Anzeige-
Elemente, jetzt auf allen drei Sensor-Seiten sichtbar (bewusst NICHT auf
der Einstellungsseite, dort ergibt ein "aktuell verwendet"-Hinweis ohne
laufende Messung keinen Sinn):

1. **`AccuracyBadge`** (`widgets/accuracy_badge.dart`, NEU) - kleines,
   farbiges Badge mit der aktuell verwendeten Genauigkeitsstufe
   (Akkusparend/Ausgewogen/Maximale Genauigkeit), Farbe fest zugeordnet
   (gelb/blau/grün, siehe `SpeedAccuracyMode.color`) und unabhängig vom
   Anzeigemodus (Hell/Dunkel) immer gleich erkennbar.
2. **`MeasurementPulseIndicator`** (`widgets/measurement_pulse_indicator.dart`,
   NEU) - blitzt kurz auf (schnelles Ein-, langsameres Ausblenden über
   700 ms), sobald sich ein von außen übergebener Zähler ändert. Kennt
   selbst keine fachliche Bedeutung von "Messung" - der jeweilige
   Aufrufer erhöht den Zähler bei genau dem Ereignis, das auf seiner
   Seite eine neue Messung darstellt.

**WICHTIG - ehrliche statt einheitlich erfundener Anzeige:** Die
Genauigkeitsstufe (`SpeedAccuracyMode`) ist bislang AUSSCHLIESSLICH auf
der Tacho-Seite über die Einstellungen wählbar (siehe Abschnitt 4) -
Kompass- und Track-Seite verwenden jeweils eine eigene, FEST
einprogrammierte Genauigkeit (`AltitudeService`: `LocationAccuracy.medium`,
siehe Abschnitt 10; `TrackRecordingService`: `LocationAccuracy.best`,
siehe Abschnitt 19), unabhängig von dieser Einstellung. Statt auf allen
drei Seiten unterschiedslos denselben (auf Kompass/Track schlicht
FALSCHEN) Einstellungswert anzuzeigen, zeigt jede Seite deshalb, was
dort TATSÄCHLICH verwendet wird:

| Seite | Woher die angezeigte Stufe stammt |
|---|---|
| Tacho | `AppPreferences.speedAccuracyMode` (echte Einstellung) |
| Kompass | `AltitudeService.fixedAccuracy` (fest: Akkusparend-Stufe) |
| Track | `TrackRecordingService.fixedAccuracy` (fest: Maximal-Stufe) |

Neue statische Methode `SpeedAccuracyMode.fromLocationAccuracy(...)`
bildet dafür eine beliebige `LocationAccuracy` auf die passende der drei
Stufen ab (die drei vordefinierten Stufen dieser App verwenden ohnehin
jeweils exakt eine von genau drei unterschiedlichen `LocationAccuracy`-
Werten, die Zuordnung ist damit eindeutig). `AltitudeService.fixedAccuracy`
bzw. `TrackRecordingService.fixedAccuracy` wurden dafür jeweils als
öffentliche Konstante freigelegt, statt die verwendete Genauigkeit ein
zweites Mal (und damit potenziell abweichend) im UI-Code zu
duplizieren.

**Auslöser des Mess-Impulses je Seite:**

| Seite | Auslöser |
|---|---|
| Tacho | jede neue `SpeedReading` |
| Kompass | jede neue `AltitudeReading` (GPS ODER Barometer) - bewusst NICHT bei jedem Magnetkompass-Update, das würde mehrmals pro Sekunde aufblitzen und die Aussagekraft ("wurde eine Standort-Messung durchgeführt") zunichtemachen |
| Track | jeder neue `TrackPoint` (erkannt über eine gestiegene Punktezahl, da der `updates`-Stream von TrackRecordingService auch aus vielen anderen Gründen feuert, z. B. Pause/Fortsetzen) |

**Platzierung:** Tacho- und Kompass-Seite zeigen die Zeile oberhalb des
bisherigen Seiteninhalts. Track-Seite zeigt sie oberhalb der in
Abschnitt 29 eingeführten Unterreiter "Karte"/"Details" (statt innerhalb
nur eines der beiden Tabs), damit sie unabhängig vom gerade gewählten
Unterreiter sichtbar bleibt - passend zur ebenfalls dort bereits
etablierten Platzierung der Start-/Pause-/Beenden-Steuerung.

**Betroffene/neue Dateien:**
- `lib/models/speed_accuracy_mode.dart` (Farbe, `fromLocationAccuracy`)
- `lib/ui/widgets/accuracy_badge.dart` (NEU)
- `lib/ui/widgets/measurement_pulse_indicator.dart` (NEU)
- `lib/services/altitude_service.dart` (`fixedAccuracy` freigelegt)
- `lib/services/track_recording_service.dart` (`fixedAccuracy` freigelegt)
- `lib/ui/speed_page.dart`
- `lib/ui/compass_page.dart`
- `lib/ui/track_page.dart`

## 38. Vermuteter Zusammenhang: Foreground-Service startet nach schnellem Beenden/Neustarten manchmal nicht

**Beobachtung:** Der sichtbare Hintergrund-Task (Foreground-Service-
Benachrichtigung "onTour zeichnet auf") startet zuverlässig mit der
ersten Aufzeichnung und endet zuverlässig mit deren Beenden. Wird jedoch
UNMITTELBAR danach eine NEUE Aufzeichnung gestartet, blieb er manchmal -
unter für den Nutzer nicht erkennbaren Umständen und OHNE jede
Fehlermeldung - aus. Spätere Wiederholungen desselben Ablaufs
funktionierten teils wieder normal.

**Recherche-Ergebnis (keine abschließend bewiesene, aber gut
begründete Diagnose):** In den GitHub-Diskussionen des geolocator-
Projekts selbst findet sich eine Entwickler-Aussage, die zu genau diesem
Muster passt: Das Plugin führt intern Buch darüber, ob "noch eine
FlutterEngine verbunden ist", bevor es den nativen Standort-Service
tatsächlich stoppt (sinngemäß: "There is still another flutter engine
connected, not stopping location service"). Unsere bewusst PERSISTENTE
FlutterEngine (Abschnitt 21) - die bei jedem App-Öffnen erneut an eine
NEUE Activity-Instanz angehängt wird, statt (wie vom Plugin
offensichtlich angenommen) exakt eine Engine pro Activity-Lebenszyklus
zu sein - passt zu genau der Konstellation, in der diese interne
Buchführung durcheinandergeraten könnte: Der vorherige Foreground-
Service wäre dann beim sofortigen Start einer neuen Aufzeichnung noch
nicht vollständig abgebaut, wodurch der neue Start-Versuch vom Plugin
stillschweigend ignoriert werden könnte - ohne dass dabei eine
abfangbare Exception anfällt (weshalb weder die in Abschnitt 30.4/36
ergänzte Fehlerbehandlung noch das Diagnose-Protokoll aus Abschnitt 34
das bislang sichtbar gemacht haben).

**WICHTIG - Einschränkung dieser Diagnose:** Ohne Einsicht in den
tatsächlich installierten geolocator-Kotlin-Quellcode bzw. einen
Stacktrace lässt sich das nicht abschließend beweisen - es handelt sich
um eine gut begründete, auf dokumentiertem Plugin-Verhalten basierende
Vermutung, keine bestätigte Ursache.

**Pragmatische Gegenmaßnahme:** `TrackRecordingService.start()` ist jetzt
`async` (vorher `void`) und wartet - falls die VORHERIGE Aufzeichnung
erst vor weniger als 800 ms beendet wurde (`_minRestartGap`) - die
verbleibende Zeit ab, BEVOR der eigentliche Positions-Stream
(re-)gestartet wird. Das gibt dem geolocator-Plugin etwas Zeit, den
Abbau des vorherigen Foreground-Service abzuschließen, bevor ein neuer
angefordert wird - eine in der Praxis übliche Gegenmaßnahme für genau
diese Art von Race Condition, auch wenn die genaue interne Ursache im
Plugin nicht einsehbar ist.

**Zusätzlich zur besseren Diagnose beim nächsten Auftreten:** Sowohl der
Beginn einer eventuellen Wartezeit als auch deren Dauer werden jetzt im
Diagnose-Protokoll (Abschnitt 34) vermerkt. Sollte das Problem trotz
dieser Wartezeit erneut auftreten, hilft ein Blick in das exportierte
Protokoll (Info-Seite) zu klären, ob zwischenzeitlich weiterhin
"Checkpoint gesichert"-Einträge erscheinen (dann liefe die eigentliche
GPS-Erfassung technisch weiter, nur die BENACHRICHTIGUNG bliebe aus)
oder ob nach dem Start gar keine weiteren Einträge mehr folgen (dann
wäre der komplette Stream betroffen, nicht nur die Benachrichtigung) -
das würde die obige Diagnose weiter eingrenzen.

**Betroffene Dateien:**
- `lib/services/track_recording_service.dart` (`start()` jetzt async,
  `_minRestartGap`, `_lastStoppedAt`)
- `lib/ui/track_page.dart` (`_handleStart` awaited jetzt `start()`)

## 39. Pause-Erinnerung: Zählrad in Minuten (ersetzt Dropdown aus Abschnitt 22/26)

Die Wartezeit der Pause-Erinnerung (Einstellungen → Erweitert) wird jetzt
über ein Zählrad (`CupertinoPicker`) in Minuten gewählt: **0 = Erinnerung
aus**, Bereich 0-120 Minuten, **Standard 3 Minuten**. Gespeichert wird eine
einfache Zahl (`AppPreferences.autoPauseReminderMinutes`, Schlüssel
`autoPauseReminderMinutes`); das Enum `AutoPauseReminderOption` samt
`models/auto_pause_reminder_option.dart` entfällt. Der zuvor unter dem
alten Schlüssel gespeicherte Wert wird nicht übernommen - es gilt wieder
der neue Standard. `TrackRecordingService.updateReminderOption` heißt jetzt
`updateReminderMinutes(int)`.

Betroffene Dateien: `app_preferences.dart`, `track_recording_service.dart`,
`track_page.dart`, `settings_page.dart`.

## 40. Stillstandserkennung der Track-Aufzeichnung (Fehlerkorrektur)

**Problem:** Während der Fahrt wurde die Aufzeichnung fälschlich
automatisch pausiert. Ursache: Die automatische Pause stützte sich allein
auf den Beschleunigungssensor (`MotionService`), der bei ruhiger,
gleichmäßiger Fahrt nahe 0 misst. Die Tacho-Seite war davon nicht
betroffen, weil sie zusätzlich die GPS-Geschwindigkeit (< 8 km/h) prüft.

**Pausieren:** Nur noch, wenn der Bewegungssensor Stillstand meldet UND
GPS ihn bestätigt (letzte GPS-Geschwindigkeit < 8 km/h, oder seit über 5 s
kein GPS-Punkt - bei `distanceFilter: 3` kommen bei Bewegung laufend Punkte).

**Fortsetzen:** Eine automatische Pause wird aufgehoben, wenn der
Bewegungssensor Bewegung meldet ODER die GPS-Geschwindigkeit ≥ 8 km/h
beträgt. Dafür läuft der GPS-Stream während einer AUTOMATISCHEN Pause
weiter (nur zur Bewegungserkennung, es werden keine Punkte gespeichert);
bei einer MANUELLEN Pause wird er wie bisher beendet. Nebenwirkung: Die
Foreground-Benachrichtigung bleibt bei einer automatischen Pause sichtbar,
der Akkuverbrauch ist dabei etwas höher. Tippt der Nutzer während einer
automatischen Pause auf "Pause", wird sie manuell und der Stream beendet.

Betroffene Datei: `track_recording_service.dart`.

## 41. Kursangaben: Kompass-Seite vs. Track-Seite

Beide Werte messen Unterschiedliches:
- **Kompass-Seite:** Ausrichtung des Geräts (Magnetfeldsensor). Seit dieser
  Änderung auf **geografisch Nord** korrigiert: `CompassService` addiert die
  Missweisung, die nativ über `GeomagneticField` (MethodChannel
  `ontour/geomagnetic`, registriert in `OnTourApplication`) für den
  aktuellen Standort ermittelt wird (neu bei Ortsänderung > ca. 0,25°).
  Ohne Standort bleibt es beim magnetischen Wert.
- **Track-Seite:** "Kurs über Grund" (GPS, Bewegungsrichtung). Wird unter
  1 m/s, bei Pause, ohne Aufzeichnung oder bei einem Wert älter als 5 s
  als "-" angezeigt.

Betroffene Dateien: `compass_service.dart`, `compass_page.dart`,
`track_recording_service.dart`, `track_page.dart`,
`native_android/.../OnTourApplication.kt`.

## 42. Profil-Diagramme: y-Achsen-Beschriftung sichtbar

Der Ankerpunkt der rechtsbündigen y-Beschriftung liegt jetzt am rechten
Rand des Beschriftungsbereichs (`_yAxisLabelWidth - 6`), der Bereich ist
von 56 auf 80 px verbreitert (`profile_chart.dart`).

## 43. Hinweis: Logcat-Rest in OnTourApplication.kt entfernt

Die in Abschnitt 33 beschlossene vollständige Entfernung der
Logcat-Aufzeichnung war in der zuletzt vorliegenden `OnTourApplication.kt`
noch nicht enthalten (`startLogcatCapture` samt Aufruf). Sie ist jetzt
entfernt (inkl. der Imports `ApplicationInfo`, `File`, `FileWriter`).

## 44. Ruhigere Höhe und Steigung (überarbeitet, ersetzt die Drosselung aus 30.2)

**Problem:** Die Steigung schwankte auch auf ebener Strecke um ±12 %. Ursache:
GPS-Höhenrauschen (mehrere Meter) schlug über die Barometer-Kalibrierung
direkt auf jeden Trackpunkt durch und wurde über kurze Punktabstände zu
großen Prozentwerten hochgerechnet.

**Maßnahmen:**
- `BarometerAltitudeService` (komplementärer Filter): Der Referenzpunkt
  (Druck/Höhe der ersten Kalibrierung) bleibt FEST. Der Luftdruck wird über
  3 s gemittelt. Der Versatz zwischen Barometer- und GPS-Höhe wird bei jeder
  GPS-Messung nur LANGSAM nachgeführt (Tiefpass, Zeitkonstante 120 s; am
  Anfang als laufender Mittelwert der ersten Messungen). Das ersetzt die
  frühere harte Neu-Kalibrierung (Stufen/Sprünge entfallen); die
  Minuten-Drosselung ist damit überflüssig. Wetterdrift wird weiterhin
  ausgeglichen. Die Position (Breite/Länge/Genauigkeit) bleibt bei jedem
  Aufruf aktuell.
- `TrackProfileCalculator`: Die Steigung wird nicht mehr aus zwei Einzelpunkten,
  sondern per linearer Regression über ein rückwärtiges Fenster von 50 m
  bestimmt (`_gradientWindowMeters`); das Fenster muss mindestens 20 m lang
  sein (`_minGradientSegmentMeters`), sonst keine Anzeige. Deckel weiterhin
  ±40 %.

**Grenzen:** Kompass-Seite und Track-Aufzeichnung nutzen weiterhin je eine
eigene `BarometerAltitudeService`-Instanz - absolute Höhenwerte beider Seiten
können um einige Meter abweichen. Der erste Trackpunkt verwendet vor der
ersten Barometer-Messung noch die GPS-Rohhöhe. Ein möglicher Ellipsoid-Versatz
der GPS-Höhe (Höhe über Ellipsoid statt über NN) ist nicht korrigiert.

## 45. Info-Seite: Button zur Play-Store-Entwicklerseite

Unter dem Autorennamen erscheint ein Button "Meine Apps im Play Store", der
die Entwicklerseite (Liste aller Apps) im Play Store öffnet
(`InfoPage._playStoreDeveloperUrl`, Paket `url_launcher`, extern geöffnet).
Solange die Konstante leer ist, wird der Button nicht angezeigt.
`AndroidManifest.xml` enthält dafür in `<queries>` einen `VIEW`-Intent für
`https` (Paketsichtbarkeit ab Android 11). Nach dem Eintragen/Hinzufügen
des Pakets `flutter pub get` ausführen.

## 46. Kompass: Gyro-Fusion und Störungswarnung

`CompassService` fusioniert den absoluten Magnetkurs (`flutter_compass`,
bereits um die Deklination auf geografisch Nord korrigiert, siehe
Abschnitt 41) mit der Drehrate des Gyroskops (`sensors_plus`) als
Complementary Filter (Zeitkonstante 1,5 s). Die Drehrate wird auf die per
Beschleunigungssensor (Tiefpass) ermittelte Lotrichtung projiziert und ist
dadurch unabhängig von der Geräteneigung. Die Anzeige wird ruhiger, folgt
Drehungen aber sofort.

**Störungserkennung:** Die Magnetfeldstärke (µT, Magnetometer) gilt als
gestört, wenn sie außerhalb von 20-75 µT liegt oder um mehr als 30 % von
einer langsam mitlaufenden Basis abweicht (Basis wird nur im ungestörten
Zustand nachgeführt). Zustandswechsel sind entprellt (1 s hinein, 2 s
hinaus, analog `MotionService`). Bei Störung wird die Korrektur zum
Magnetkurs ausgesetzt, der Kurs läuft nur auf dem Gyro weiter. Weicht der
Magnetkurs bei ungestörtem Feld länger als 8 s um mehr als 30° ab, obwohl
das Gerät fast still gehalten wird (< 10 °/s), wird neu synchronisiert
(Gyro-Drift). Ohne Gyroskop wird der Magnetkurs wie bisher durchgereicht,
ohne Magnetometer entfällt die Störungswarnung.

**Anzeige:** `CompassPage` zeigt in der Statuszeile (feste Höhe, kein
Layout-Sprung) den Chip "Kompass gestört"; Antippen öffnet seit Abschnitt 48
die geführte Kalibrierung (zuvor ein reiner Hinweisdialog). Die
Kurs-Genauigkeitszeile zeigt dann "Genauigkeit: gestört".

**Hinweise:** Alle Schwellenwerte sind empirische Startwerte und auf dem
Gerät zu verifizieren. `CompassPage.dispose()` gibt den Service jetzt frei
(mehrere Sensor-Subscriptions). Das Gyroskop läuft nur, solange die
Kompass-Seite sichtbar ist.

**Betroffene Dateien:**
- `lib/models/compass_reading.dart` (neue Felder `isDisturbed`,
  `fieldStrengthMicroTesla`)
- `lib/services/compass_service.dart` (Fusion, Störungserkennung,
  `dispose`)
- `lib/ui/compass_page.dart` (Chip, Dialog, Genauigkeitszeile, dispose)

## 47. Luftdruck-Anzeige mit 3-Stunden-Trend (Kompass-Seite)

Der Barometer (`sensors_plus`) liefert jetzt zusätzlich zur Höhe den
Luftdruck samt Tendenz. Ein schneller Druckabfall ist besonders für Segler
ein wichtiges Warnsignal.

**`services/pressure_trend_service.dart` (NEU):** Lebt - wie
`TrackRecordingService` - einmalig in `HomeShell` (nicht pro Seitenaufruf),
da ein Trend den Verlauf über Stunden braucht. Der Druck wird fortlaufend
gelesen und jeweils über eine Minute gemittelt (eine Probe pro Minute,
Verlauf max. 4 Stunden). Der Trend ist die Steigung einer Ausgleichsgeraden
(lineare Regression) über das 3-Stunden-Fenster, hochgerechnet auf hPa pro
3 Stunden - robuster gegen Rauschen und Lücken als die Differenz zweier
Werte. Ein Trend erscheint ab 30 Minuten Verlauf (bei weniger als 3 Stunden
mit dem Hinweis "Basis: X min"). Der Verlauf wird alle 5 Minuten als Datei
(`ontour_pressure_history.json`, Dokumentenverzeichnis) gesichert und beim
Start wieder geladen, damit ein App-Neustart den Trend nicht zurücksetzt.

**`models/pressure_reading.dart` (NEU):** `PressureReading` sowie die
Stufen `PressureTrendCategory` (hPa/3 h): gleichbleibend < 1,0;
fallend/steigend 1,0-3,5; schnell 3,5-6,0; sehr schnell > 6,0. Die
Schwelle von 1,0 hPa für "gleichbleibend" berücksichtigt, dass
Smartphone-Barometer über Stunden um einige Zehntel hPa driften können.

**Anzeige:** Auf der Kompass-Seite unter der Höhe: "Luftdruck: 1009,3 hPa"
(Schriftgröße wie Kurs/Höhe), darunter der Trend im kleineren Stil
(z. B. "↘ fallend: -2,1 hPa / 3 h"). Eine Zusatzzeile erscheint nur bei
Bedarf (kurzer Verlauf bzw. Höhenänderung). Solange kein Wert vorliegt:
"Luftdruck: nicht verfügbar".

**WICHTIG - Stationsdruck, nicht Meeresspiegeldruck:** Angezeigt wird der am
Gerät GEMESSENE Druck. Wetterberichte geben den auf Meereshöhe umgerechneten
Druck an; beide unterscheiden sich pro 100 m Höhe um rund 12 hPa. Auf See
ist der Unterschied vernachlässigbar, im Binnenland/Gebirge nicht. Eine
Umrechnung wurde bewusst NICHT eingebaut: Die GPS-Höhe (u. U. Höhe über dem
Ellipsoid, in Deutschland ca. 45-50 m über NN, siehe Abschnitt 44) würde
den umgerechneten Wert um mehrere hPa verfälschen.

**Einschränkungen:** (1) Im Hintergrund liefert Android Sensorwerte nicht
garantiert - der Verlauf kann Lücken haben (die Regression kommt damit
zurecht). (2) Eine Höhenänderung (ca. 1,2 hPa pro 10 m) lässt sich vom Wetter
nicht trennen. `CompassPage` meldet ihre Höhenwerte über
`PressureTrendService.noteAltitude`; ändert sich die Höhe im Fenster um mehr
als 15 m, erscheint "Höhe geändert - Trend unsicher". Höhen, die nur auf
anderen Seiten (z. B. Track) bekannt sind, fließen nicht ein. (3) Der Textblock
der Kompass-Seite hat jetzt zwei bis drei Zeilen mehr; das vorhandene
`FittedBox` skaliert ihn bei Bedarf etwas kleiner.

**Betroffene/neue Dateien:**
- `lib/models/pressure_reading.dart` (NEU)
- `lib/services/pressure_trend_service.dart` (NEU)
- `lib/ui/home_shell.dart` (hält den Service, startet/beendet ihn, reicht
  ihn an `CompassPage` durch)
- `lib/ui/compass_page.dart` (neuer Parameter `pressureService`, Anzeige)

## 48. Geführte Kompass-Kalibrierung

**Motivation:** Bei gestörtem Kompass (Abschnitt 46) gab es nur einen
Hinweisdialog. Neu: `ui/compass_calibration_page.dart` führt den Nutzer
durch die Bewegung, die Android für die Selbstkalibrierung des
Magnetsensors braucht, und zeigt das Ergebnis an.

**WICHTIG - was die Seite NICHT kann:** Android bietet Apps keine
Möglichkeit, die Magnetsensor-Kalibrierung selbst auszulösen oder
Kalibrierwerte zu setzen; das System justiert den Sensor eigenständig,
während das Gerät bewegt wird. Die Seite rechnet deshalb nichts am Sensor
um, sondern (1) zeigt per Animation die gewünschte Bewegung (liegende
Acht, `_FigureEightPainter`), (2) misst, wie vollständig das Gerät dabei
gedreht/gekippt wurde, und (3) bestätigt, sobald das Magnetfeld wieder
plausibel ist. Eine ÄUSSERE Störung (Karosserie, Magnethalterung, Metall)
lässt sich so nicht beheben - die Seite weist dann darauf hin.

**Bewegungsabdeckung:** Die Richtung des rohen Magnetfeldvektors im
Gerätekoordinatensystem wird in 8 x 4 Kacheln (Azimut x Elevation)
eingeteilt; durchlaufene Kacheln zählen als erfasst. Ab 40 % der Kacheln
gilt die Bewegung als ausreichend (nicht alle Kacheln sind bei normaler
Handbewegung erreichbar). Der Fortschrittsbalken zeigt diese Abdeckung.

**Abschluss:** "Fertig" erscheint, sobald genug Bewegung erfasst wurde UND
der `CompassService` das Feld als ungestört meldet (derselbe, entprellte
Wert wie der Warn-Chip). Der Zustand bleibt bis "Neu starten" bestehen.
Bleibt das Feld trotz genug Bewegung gestört, erscheint ein Hinweis auf
äußere Störquellen.

**Einstieg:** Warn-Chip "Kompass gestört" UND ein dauerhaft sichtbarer
Button (Icon `threesixty`) in der Statuszeile der Kompass-Seite - die
Kalibrierung ist auch ohne Störungswarnung erreichbar. Die Seite hört als
zweiter Listener auf den bereits laufenden `CompassService`-Stream der
Kompass-Seite (kein zusätzlicher Sensor-Start dort); nur das rohe
Magnetometer für die Abdeckung wird zusätzlich gelesen.

**Betroffene/neue Dateien:**
- `lib/ui/compass_calibration_page.dart` (NEU)
- `lib/ui/compass_page.dart` (Chip und Button öffnen die Seite; der
  Hinweisdialog aus Abschnitt 46 entfällt)

## 49. Automatische Pause: rein GPS-basierte Stillstandserkennung

**Problem:** Bei laufendem Motor im Leerlauf (Ampel) halten die
Fahrzeugvibrationen den Beschleunigungssensor dauerhaft auf "Bewegung".
Die bisherige Pause-Erkennung (Abschnitt 40: Sensor meldet Stillstand UND
GPS bestätigt) löste dadurch nur bei abgeschaltetem Motor aus. Umgekehrt
hätte der Sensor eine Pause sofort wieder aufgehoben.

**Neu (`TrackRecordingService`):**
- **Pausieren per GPS allein:** Ein sekündlicher Timer (`_checkGpsStandstill`)
  prüft, ob die letzte GPS-Geschwindigkeit unter 0,5 m/s (1,8 km/h) liegt
  oder seit 5 s kein neuer Punkt eintraf (bei `distanceFilter: 3` kommen im
  Stand keine Punkte). Hält das 8 s ununterbrochen an, wird automatisch
  pausiert. Die Schonfrist nach manuellem Fortsetzen (10 s) gilt weiter. Der
  bisherige Pfad (Sensor meldet Stillstand + GPS bestätigt) bleibt als
  schnellerer Weg erhalten (z. B. Motor aus).
- **Fortsetzen nur per GPS:** Eine automatische Pause wird NICHT mehr durch
  den Bewegungssensor aufgehoben, sondern erst, wenn zwei aufeinanderfolgende
  GPS-Messwerte mindestens 1,0 m/s (3,6 km/h) zeigen. Die Schwelle liegt
  bewusst über der Pausenschwelle (Hysterese); die zwei Bestätigungen
  fangen einzelne GPS-Ausreißer im Stand ab. Sie ist niedriger als zuvor
  (8 km/h), damit auch Fußgänger zuverlässig wieder einsteigen.

**Nebenwirkungen:** Ein GPS-Verlust (Tunnel) führt nach ca. 13 s zu einer
automatischen Pause; die Aufzeichnung wird mit den ersten gültigen
Geschwindigkeitswerten fortgesetzt (die Tunnelzeit zählt nicht zur Dauer;
Punkte fehlen dort ohnehin). Sehr langsames Kriechen unter 1,8 km/h gilt als
Stillstand. Alle Schwellen (`_gpsStandstillMaxSpeedMs`,
`_gpsStandstillConfirmDuration`, `_gpsResumeMinSpeedMs`) sind Startwerte.

**Betroffene Datei:** `lib/services/track_recording_service.dart`

## 50. Ortssuche und Ziel auf der Track-Seite (Karte)

Auf dem Unterreiter "Karte" der Track-Seite lässt sich ein Ort suchen und als
Ziel markieren.

**Bedienung:**
- **Lupe** (links oben): öffnet eine Suchmaske (`widgets/place_search_sheet.dart`)
  mit Suchfeld und Ergebnisliste. Gesucht wird nur auf ausdrücklichen Befehl
  (Tastatur-"Suchen" bzw. Lupe im Feld), nicht bei jeder Eingabe. Ein Antippen
  eines Treffers setzt das Ziel und zeigt eigene Position und Ziel im Bild.
- **Langes Drücken auf die Karte** markiert den Punkt als Ziel ("Markierter
  Punkt"), ohne die Karte zu verschieben.
- **Zielmarker:** rote Nadel (`Icons.place`), die Spitze liegt auf dem Ziel.
- **Zielkarte** (oben, neben den Karten-Buttons): Zielname sowie Luftlinie und
  Richtung (Grad) von der eigenen Position, sobald bekannt. Antippen zeigt das
  Ziel auf der Karte, das Kreuz entfernt es.
- Das Ziel bleibt über App-Neustarts erhalten (`AppPreferences.destination`,
  JSON in `shared_preferences`, Schlüssel `destination`).

**Suchdienst (`services/place_search_service.dart`, NEU):** Nominatim von
OpenStreetMap (kostenlos, ohne API-Key, passend zu den OSM-Kacheln), nur über
`dart:io` - keine neue Paketabhängigkeit; `INTERNET` ist bereits im Manifest.
Bewusst eingehaltene Nutzungsbedingungen des öffentlichen Servers: höchstens
1 Anfrage pro Sekunde, eigener User-Agent (`onTour/1.0 (de.clausjbauer.ontour)`),
KEINE Autovervollständigung, Quellenangabe in der Suchmaske. Fehler (kein Netz,
Zeitüberschreitung, Dienstfehler) erscheinen als verständliche Meldung.
**Für starke Nutzung (z. B. viele Nutzer im Play Store) ist der öffentliche
Server nicht vorgesehen** - dann wäre ein eigener oder kommerzieller
Geocoding-Dienst nötig.

**Was es (noch) NICHT ist:** keine Routenführung - angezeigt werden nur
Luftlinie und Richtung zum Ziel, keine Strecke über Straßen. Das Ziel wird auch
auf der Kompass-Seite noch nicht berücksichtigt (denkbar als nächster Schritt:
Peilung zum Ziel auf der Kompassrose).

**Hinweis zur Karte:** Während einer laufenden Aufzeichnung führt die Karte
sonst bei jedem Punkt zur eigenen Position; nach Anzeige des Ziels ist dieses
Mitführen 20 Sekunden ausgesetzt, damit das Ziel nicht sofort wieder aus dem
Bild springt.

**Betroffene/neue Dateien:**
- `lib/models/place_result.dart` (NEU)
- `lib/services/place_search_service.dart` (NEU)
- `lib/ui/widgets/place_search_sheet.dart` (NEU)
- `lib/services/app_preferences.dart` (`destination`, `setDestination`)
- `lib/ui/track_page.dart` (Lupe, Zielkarte, Marker, langes Drücken)

## 51. Wählbare Basiskarten und Karten-Einstellungen

Neben der Standard-OSM-Karte stehen jetzt zwei Wanderkarten zur Wahl
(`models/map_style.dart`, `MapStyle`): **OpenTopoMap-R** (openmaps.fr,
`https://tile.openmaps.fr/opentopomap/{z}/{x}/{y}.png`) und die **Reit- und
Wanderkarte** (`https://topo.wanderreitkarte.de/topo/{z}/{x}/{y}.png`).
Das Seemarken-Overlay (Abschnitt 9) bleibt ein eigener Schalter und lässt
sich über jede Basiskarte legen.

**Bedienung:** Der frühere Landkarte/Seekarte-Button (`NauticalModeButton`)
auf Track-Seite und Track-Detailansicht ist durch den Karten-Button
(`widgets/map_style_button.dart`, Symbol "Ebenen") ersetzt - er öffnet ein
Auswahlfenster mit den drei Basiskarten und dem Seemarken-Schalter. Dieselbe
Auswahl gibt es unter Einstellungen → Karten (neuer dritter Unterreiter,
zwischen "Anzeige" und "Erweitert"), dort zusätzlich mit Quellen und
Nutzungshinweisen je Anbieter. Gespeichert wird beides über dieselben Werte
in `AppPreferences` (`mapStyle`, `mapNauticalMode`); der bisherige
Seekarten-Wert bleibt unverändert gültig. `widgets/nautical_mode_button.dart`
wird nicht mehr verwendet und kann gelöscht werden.

**Quellenangabe (Lizenzvoraussetzung):** Die Reit- und Wanderkarte steht
unter CC-BY-NC-SA und verlangt mindestens den Text "Reit- und Wanderkarte"
mit Link auf www.wanderreitkarte.de sowie einen Lizenzhinweis. Bei dieser
Karte wird die Angabe deshalb DAUERHAFT sichtbar am unteren rechten Kartenrand
angezeigt (antippbar, `MapStyle.alwaysVisibleAttribution`); die Statuskarte
der Track-Aufzeichnung rückt dafür etwas nach oben. Bei den anderen Karten
bleibt es beim aufklappbaren Info-Symbol. Zusätzlich führt die Info-Seite
einen Abschnitt "Kartenmaterial" mit allen Quellen.

**Nutzungsbedingungen (Kurzfassung, Details in den Einstellungen):**
- Reit- und Wanderkarte: nur kostenlos und nicht-kommerziell; von
  werbefinanzierten/gewerblichen Angeboten wird eine Beteiligung an den
  Serverkosten erwartet; Limit 40.000 Kacheln pro Tag (bei Überschreitung 24
  Stunden Sperre, ein IP-Wechsel zur Umgehung ist untersagt), kein
  Massen-Download. Vor der Veröffentlichung im Play Store sollte der Betreiber
  kurz kontaktiert werden.
- OpenTopoMap-R: kostenlos für nicht-kommerzielle Projekte; festes Limit
  500.000 Kacheln pro Monat (darüber Einschränkung), kein Massen-Download,
  Zugriff kann ohne Vorankündigung gesperrt werden. Die Policy verlangt eine
  OHNE Antippen sichtbare Quellenangabe (Stil, Spendenlink, OpenStreetMap) -
  deshalb wie bei der Reit- und Wanderkarte dauerhaft angezeigt.
- Alle Karten: https (Android blockiert unverschlüsselten Verkehr
  standardmäßig). Die in der Anleitung des Betreibers genannte
  `http://`-Adresse der Reit- und Wanderkarte wurde deshalb auf `https://`
  umgestellt - funktioniert der Abruf nicht, ist ein Ausnahmeeintrag per
  `networkSecurityConfig` für `topo.wanderreitkarte.de` nötig.

**Fehlerkorrektur - User-Agent:** openmaps.fr lieferte zunächst statt
Kacheln das Bild "Limited Access ... does not respect our Usage Policy
regarding User-Agent". Ursache: flutter_map sendet über
`userAgentPackageName` den Wert "flutter_map (de.clausjbauer.ontour)" - die
Policy verlangt aber einen die ANWENDUNG benennenden Wert und lehnt
Bibliotheks-Standardwerte ab. `buildMapTileLayers` setzt deshalb für alle
Kachelebenen den Header `User-Agent: onTour/1.0 (de.clausjbauer.ontour)`
(`NetworkTileProvider(headers: ...)`). Falls weiterhin die Fehlerkacheln
erscheinen, liegen sie evtl. noch im Kachel-Cache: App-Daten löschen bzw.
App neu installieren.

**Zu prüfen auf dem Gerät:** `MapStyle.maxNativeZoom` ist für beide
Wanderkarten vorsichtig auf 17 gesetzt (darüber werden Kacheln nur
vergrößert, nie leer). Liefert ein Server höhere Stufen, kann der Wert
angehoben werden.

**Betroffene/neue Dateien:**
- `lib/models/map_style.dart` (NEU)
- `lib/util/external_link.dart` (NEU)
- `lib/ui/widgets/map_style_button.dart` (NEU)
- `lib/ui/widgets/map_tile_layers.dart` (Basiskarte, Attribution)
- `lib/services/app_preferences.dart` (`mapStyle`)
- `lib/ui/track_page.dart`, `lib/ui/track_detail_page.dart`
- `lib/ui/settings_page.dart` (Unterreiter "Karten")
- `lib/ui/info_page.dart` (Abschnitt "Kartenmaterial")

## 52. Weitere Basiskarten (TopPlusOpen, CyclOSM) und Routen-Overlay (Waymarked Trails)

Erweitert die Kartenauswahl aus Abschnitt 51. Die App spricht ausdrücklich
auch Radfahrer an.

**Neue Basiskarten (`MapStyle`):**
- **TopPlusOpen** (Bundesamt für Kartographie und Geodäsie, BKG): amtliche,
  ruhige Referenzkarte, kein Schlüssel. URL
  `https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web/default/WEBMERCATOR/{z}/{y}/{x}.png`
  - ACHTUNG: Reihenfolge `{z}/{y}/{x}`. Bedingung: deutlich sichtbarer
  Quellenvermerk "© BKG (Jahr des letzten Datenbezugs) dl-de/by-2-0,
  Datenquellen: (Link)" - wird dauerhaft angezeigt. **Das Jahr in
  `map_style.dart` (aktuell 2026) sollte jährlich geprüft werden.** Die
  Karte zeigt weder Wanderwege noch Höhenlinien.
- **CyclOSM** (OpenStreetMap-France):
  `https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png`, es gilt
  die allgemeine OSM-Tile-Usage-Policy ("fair use").

**Routen-Overlay (`models/route_overlay.dart`, `RouteOverlay`):** Aus,
Wanderrouten oder Radrouten (`https://tile.waymarkedtrails.org/hiking|cycling/{z}/{x}/{y}.png`,
Waymarked Trails, CC-BY-SA). Die drei Zustände schließen sich gegenseitig
aus; das Seemarken-Overlay bleibt davon unabhängig. Gespeichert über
`AppPreferences.routeOverlay`. **Nutzungsbedingungen von Waymarked Trails
konnte ich nicht abschließend prüfen** (keine Policy gefunden) - Quellenangabe
ist erforderlich (Layer wird in der Quellenangabe der Karte genannt), bei
größerer Nutzerzahl den Betreiber kontaktieren.

**Bedienung:** Karten-Button (Abschnitt 51) und Einstellungen → Karten
enthalten jetzt fünf Basiskarten, die Routen-Auswahl und den
Seemarken-Schalter; die Quellenkarten in den Einstellungen und der Abschnitt
"Kartenmaterial" der Info-Seite führen auch die Overlays. Die Statuskarte der
Track-Aufzeichnung rückt bei dauerhaft sichtbarer Quellenangabe mit
zusätzlichem Overlay etwas weiter nach oben (längere Quellenzeile).

**Zu prüfen auf dem Gerät:** Lesbarkeit der (dann ggf. zweizeiligen)
Quellenangabe auf kleinen Displays; Darstellung der Routenlinien über
OpenTopoMap-R und der Reit- und Wanderkarte (die bereits eigene Wanderwege
zeigen); höchste Zoomstufen der neuen Karten.

**Betroffene/neue Dateien:**
- `lib/models/route_overlay.dart` (NEU)
- `lib/models/map_style.dart` (TopPlusOpen, CyclOSM)
- `lib/services/app_preferences.dart` (`routeOverlay`)
- `lib/ui/widgets/map_tile_layers.dart`, `lib/ui/widgets/map_style_button.dart`
- `lib/ui/track_page.dart`, `lib/ui/track_detail_page.dart`
- `lib/ui/settings_page.dart`, `lib/ui/info_page.dart`

## 53. Legende der angezeigten Karte

Neuer Button "Legende" (Symbol `legend_toggle`, `widgets/map_legend_button.dart`)
auf Track-Seite und Track-Detailansicht, in der LINKEN UNTEREN Ecke der Karte
(damit die Button-Reihe am rechten Rand kurz bleibt). Bei laufender oder
pausierter Aufzeichnung sitzt er über der Statuskarte, bei dauerhaft sichtbarer
Quellenangabe über dieser - die Höhen sind feste Näherungswerte und ggf. auf
dem Gerät nachzujustieren. Er öffnet ein
Fenster, das sich nach der AKTUELLEN Auswahl richtet:
- **Basiskarte:** kurze Hinweise zum Kartenbild (`MapStyle.legendHints`) und
  ein Button "Vollständige Legende öffnen" (`MapStyle.legendUrl`, öffnet im
  Browser).
- **Routen-Overlay** und **Seemarken**, sofern eingeschaltet (eigener
  Abschnitt mit Hinweis und Link).
- **Symbole in onTour:** rote Linie (Track), Positions-, Ziel-, Start- und
  Ende-Symbol - diese Symbole gehören zur App selbst und sind unabhängig von der
  gewählten Karte.

**Bewusste Grenze:** Die Kartenkacheln kommen als fertige Bilder von
Fremdanbietern; eine vollständige Zeichenerklärung gibt es nur beim jeweiligen
Anbieter, und eigene Nachbildungen wären ohne Quelle fehleranfällig. Die App
zeigt deshalb nur Hinweise, die aus Anbieterdokumentation stammen (z. B.
Farbbedeutung bei CyclOSM, Wegedarstellung der Reit- und Wanderkarte), und
verlinkt die vollständige Legende. Für TopPlusOpen und die Waymarked-Trails-
Overlays habe ich keine eigene Zeichenerklärung gefunden - dort verweist der
Link auf die Produktbeschreibung bzw. die Webseite des Anbieters. Die Legenden-
Links können sich ändern (Anbieter-Webseiten).

**Betroffene/neue Dateien:**
- `lib/ui/widgets/map_legend_button.dart` (NEU)
- `lib/models/map_style.dart`, `lib/models/route_overlay.dart`
  (`legendUrl`, `legendHints`)
- `lib/ui/track_page.dart`, `lib/ui/track_detail_page.dart`

## 54. Höhenkorrektur: NN-Umrechnung (Android 14+) und manuelle Kalibrierung

**Problem:** Die angezeigte Höhe lag bei mehreren Testern deutlich daneben
(z. B. in Linsburg gut 20 m zu hoch). GPS misst über dem WGS84-Ellipsoid, nicht
über NN; in Norddeutschland liegt das Geoid ca. 45-47 m darüber. Je nach Gerät
liefert `Position.altitude` Ellipsoid- oder NN-Höhe. Zusätzlich übernahm der
Barometer (Abschnitt 44) die erste GPS-Höhe als festen Referenzpunkt, ein
Anfangsfehler blieb also dauerhaft erhalten. Die genaue Ursache ist noch nicht
bestätigt - das Diagnose-Protokoll (siehe unten) soll das klären.

**Stufe 1 - automatische NN-Korrektur (`services/altitude_correction.dart`):**
Neuer MethodChannel `ontour/altitude` (Methode `mslAltitude`, registriert in
`OnTourApplication`). Er liest den letzten GPS-Fix (`getLastKnownLocation`) und
liefert `Location.getAltitude()` (derselbe Wert wie `Position.altitude`) sowie
`getMslAltitudeMeters()` (ab Android 14). Die Differenz ist die Korrektur; sie
wird auf die GPS-Höhe addiert, bevor sie als Barometer-Referenz oder Trackpunkt
dient. Liefert ein Gerät `altitude` bereits als NN-Höhe, ergibt sich ca. 0.
Abfrage höchstens alle 5 min (bis zum ersten Erfolg alle 20 s). Korrekturen
über ±110 m werden verworfen. Unter Android < 14 gibt es keine Korrektur.

**Stufe 2 - manueller Versatz:** Kompass-Seite, Symbol "Höhe kalibrieren": bekannte
Höhe eingeben, der Versatz zur angezeigten Höhe wird in `AppPreferences`
(`altitudeManualOffsetMeters`) gespeichert und nur auf den Endwert (Anzeige und
Trackpunkte) addiert. Zurücksetzen im Dialog oder unter Einstellungen →
Erweitert. Am besten einige Minuten nach dem Start kalibrieren, weil der
Barometer seinen Versatz zu GPS erst langsam (120 s) findet.

**Diagnose:** In Nicht-Release-Builds schreibt `refreshIfDue` Android-Höhe,
MSL-Höhe, Korrektur, `Position.altitude`, angezeigte Höhe und manuellen Versatz
ins Diagnose-Protokoll (Abschnitt 34). Der Kalibrierdialog zeigt Korrektur und
Versatz auch in Release-Builds.

**Betroffene/neue Dateien:** `lib/services/altitude_correction.dart` (NEU),
`lib/services/app_preferences.dart`, `lib/services/track_recording_service.dart`,
`lib/ui/compass_page.dart`, `lib/ui/settings_page.dart`,
`native_android/.../OnTourApplication.kt`.

## 55. Höhenkorrektur: NN-Umrechnung (Android 14+) und manuelle Kalibrierung

**Problem:** Die angezeigte Höhe lag bei mehreren Testern deutlich daneben
(z. B. in Linsburg gut 20 m zu hoch). GPS misst über dem WGS84-Ellipsoid, nicht
über NN; in Norddeutschland liegt das Geoid ca. 45-47 m darüber. Je nach Gerät
liefert `Position.altitude` Ellipsoid- oder NN-Höhe. Zusätzlich übernahm der
Barometer (Abschnitt 44) die erste GPS-Höhe als festen Referenzpunkt, ein
Anfangsfehler blieb also dauerhaft erhalten. Die genaue Ursache ist noch nicht
bestätigt - das Diagnose-Protokoll (siehe unten) soll das klären.

**Stufe 1 - automatische NN-Korrektur (`services/altitude_correction.dart`):**
Neuer MethodChannel `ontour/altitude` (Methode `mslAltitude`, registriert in
`OnTourApplication`). Er liest den letzten GPS-Fix (`getLastKnownLocation`) und
liefert `Location.getAltitude()` (derselbe Wert wie `Position.altitude`) sowie
`getMslAltitudeMeters()` (ab Android 14). Die Differenz ist die Korrektur; sie
wird auf die GPS-Höhe addiert, bevor sie als Barometer-Referenz oder Trackpunkt
dient. Liefert ein Gerät `altitude` bereits als NN-Höhe, ergibt sich ca. 0.
Abfrage höchstens alle 5 min (bis zum ersten Erfolg alle 20 s). Korrekturen
über ±110 m werden verworfen. Unter Android < 14 gibt es keine Korrektur.

**Stufe 2 - manueller Versatz:** Kompass-Seite, Symbol "Höhe kalibrieren": bekannte
Höhe eingeben, der Versatz zur angezeigten Höhe wird in `AppPreferences`
(`altitudeManualOffsetMeters`) gespeichert und nur auf den Endwert (Anzeige und
Trackpunkte) addiert. Zurücksetzen im Dialog oder unter Einstellungen →
Erweitert. Am besten einige Minuten nach dem Start kalibrieren, weil der
Barometer seinen Versatz zu GPS erst langsam (120 s) findet.

**Diagnose:** In Nicht-Release-Builds schreibt `refreshIfDue` Android-Höhe,
MSL-Höhe, Korrektur, `Position.altitude`, angezeigte Höhe und manuellen Versatz
ins Diagnose-Protokoll (Abschnitt 34). Der Kalibrierdialog zeigt Korrektur und
Versatz auch in Release-Builds.

**Betroffene/neue Dateien:** `lib/services/altitude_correction.dart` (NEU),
`lib/services/app_preferences.dart`, `lib/services/track_recording_service.dart`,
`lib/ui/compass_page.dart`, `lib/ui/settings_page.dart`,
`native_android/.../OnTourApplication.kt`.

## 56. Start-Seite mit Profilen (Wandern / Segeln / Rad-Moto / Wohnmobil / Eigene)

**Idee:** Statt direkt auf dem Tacho zu starten, öffnet die App jetzt eine
Start-/Übersichtsseite. Links steht eine vertikale Leiste mit den Profilen,
rechts erscheinen die zum Profil passenden Anzeigen ("Slots") als Kacheln.
Das gewählte Profil ist in der Leiste hervorgehoben und bleibt über
App-Neustarts erhalten. Solange noch kein Profil gewählt wurde, fragt ein
Hinweis "Wie bist du unterwegs?".

**Navigation (geändert):** Fünf Tabs - Start, Tacho, Kompass, Track,
Einstellungen. Start ist der erste Tab und der Start-Tab der App. Der
Track-Tab hat dadurch jetzt Index 3 (`HomeShell._trackTabIndex`, wichtig für
den Sprung aus der Pause-Erinnerung, Abschnitt 23). Wegen fünf Einträgen
nutzt HomeShell jetzt `AppNavigationBar` (Silbentrennung statt abgeschnittener
Beschriftung wie bei "Einstellungen").

**Slot-Katalog (`models/user_profile.dart`, `SlotType`):** Tempo, Kurs über
Grund, Höhe, Luftdruck, Position, Kompass, Kartenvorwahl. Ein Profil
(`UserProfile`) ist nur eine Liste dieser Bausteine plus Anfangseinheit und
Kartenvorwahl:

| Profil | Einheit | Slots | Kartenvorwahl |
|---|---|---|---|
| Wandern | m/s | Tempo, Höhe, Luftdruck, Kompass, Position, Karte | Reit- und Wanderkarte + Wanderrouten |
| Segeln | kn | Tempo, Kurs, Luftdruck, Position, Kompass, Karte | Standard + Seemarken |
| Rad / Moto | km/h | Tempo, Höhe, Kurs, Kompass, Luftdruck, Karte | CyclOSM + Radrouten |
| Wohnmobil | km/h | Tempo, Höhe, Luftdruck, Position, Kompass, Karte | TopPlusOpen |
| Eigene | km/h | Tempo, Kurs, Höhe, Position, Kompass, Luftdruck | keine |

**Einheit je Profil:** Beim Wählen eines Profils wird die zuletzt dafür
verwendete (sonst die Standard-)Einheit eingestellt. Ändert der Nutzer die
Einheit später (z. B. auf der Tacho-Seite), merkt sich das aktive Profil
diese Wahl. Dadurch bleiben Start- und Tacho-Seite konsistent
(`AppPreferences.setUserProfile`/`setSpeedUnit`).

**Kartenvorwahl:** Die Kachel setzt Basiskarte, Routen-Overlay und
Seemarken für die Track-Seite - aber nur auf Tipp auf "Übernehmen", nie
automatisch beim Profilwechsel (`AppPreferences.applyMapPreset`). Ist die
Vorwahl schon aktiv, zeigt die Kachel "Aktiv".

**Sensoren (`services/live_data_service.dart`):** Die Seite abonniert nur,
was die belegten Slots brauchen. Ein GPS-Stream liefert Tempo, Kurs, Höhe
und Position (Tempo mit derselben Stillstandskorrektur wie der Tacho:
Bewegungssensor UND GPS < 8 km/h). Der Barometer läuft nur bei belegtem
Höhen-Slot (gleiche Kalibrierung und NN-Korrektur wie Kompass-Seite), der
Kompass samt Gyro nur bei belegtem Kompass-Slot, der Luftdruck kommt aus
dem ohnehin laufenden `PressureTrendService`. Beim Verlassen der Seite
stoppt alles. Änderungen werden auf höchstens einen Neuaufbau je 200 ms
gebündelt, die Kompassrose aktualisiert sich über einen eigenen
`ValueNotifier`. Der Bildschirm bleibt wach, solange die Seite sichtbar ist
(wie bei Tacho und Kompass).

**Bedienung:** Eine Kachel antippen öffnet die Vollansicht (Tempo -> Tacho;
Höhe, Luftdruck, Position, Kompass -> Kompass). Kurs und Kartenvorwahl
haben keine Vollansicht.

**Bewusst noch NICHT enthalten (nächste Ausbaustufe):**
- Einstellungsbereich zum Anpassen der Slot-Belegung (und damit die freie
  Belegung von "Eigene"). Die Speicherung ist schon vorbereitet
  (`AppPreferences.slotsFor`/`setSlotsFor`/`resetSlotsFor`), es fehlt nur
  die Oberfläche.
- Schrittzähler: braucht die Berechtigung ACTIVITY_RECOGNITION (Android 10+)
  samt Laufzeitabfrage, und der Sensor zählt nur seit dem Gerätestart. Bis
  dahin belegt beim Wandern die Position den Platz.
- Stellplatz-POIs für Wohnmobilisten.

**Zu prüfen auf dem Gerät:** Kachelhöhe und Lesbarkeit der Position auf
schmalen Displays (zwei Spalten neben der 80 dp breiten Leiste),
Beschriftung der Leiste ("Wohnmobil"), Akkuverbrauch mit sechs belegten
Slots.

**Betroffene/neue Dateien:**
- `lib/models/user_profile.dart` (NEU)
- `lib/services/live_data_service.dart` (NEU)
- `lib/ui/start_page.dart` (NEU)
- `lib/services/app_preferences.dart` (Profil, Einheit je Profil, Slots,
  Kartenvorwahl)
- `lib/ui/home_shell.dart` (fünf Tabs, `AppNavigationBar`, Track-Index 3)

## 57. Start-Seite: einstellbare Spalten und Einstellungsbereich "Start"

**Spalten (`models/start_grid_columns.dart`, `StartGridColumns`):** Die
Kacheln der Start-Seite stehen je nach Einstellung in einer oder zwei
Spalten - Automatisch (Standard), 1 Spalte oder 2 Spalten. "Automatisch"
wählt anhand der Breite des Kachelbereichs (neben der Profil-Leiste): unter
480 dp eine Spalte (Smartphone), sonst zwei (Tablet, Faltgerät).

**Einspaltig (Smartphone):** Textwerte (Tempo, Kurs, Höhe, Luftdruck,
Position, Kartenvorwahl) sind flache Kacheln von 80-96 dp Höhe -
Symbol und Beschriftung (mit Zusatzzeile, z. B. Genauigkeit) links, der Wert
rechtsbündig. Die Kompassrose bekommt den übrigen Platz der Seite
(mindestens 200, höchstens 380 dp) und erscheint dadurch größer als im
Zwei-Spalten-Raster. Ist kein Kompass belegt, bleiben alle Kacheln flach, die
Seite scrollt bei Bedarf. **Zweispaltig:** wie in Abschnitt 56 (höhere
Kacheln, großer Wert in der Mitte).

**Einstellungen -> Start (neuer Unterreiter, zweiter von vier):**
- Spaltenanzahl (Auto / 1 Spalte / 2 Spalten).
- Anzeigen je Profil: Profil per Chip wählen (zeigt zunächst das aktive
  Profil), Anzeigen per Griff-Symbol umsortieren, per Minus-Symbol entfernen
  (mindestens eine bleibt), per "Anzeige hinzufügen" aus den noch freien
  ergänzen, per "Standard wiederherstellen" zurücksetzen. Jede Anzeige gibt
  es höchstens einmal je Profil. Die Kartenvorwahl lässt sich nur bei
  Profilen hinzufügen, die eine Karte vorwählen (nicht bei "Eigene"). Damit
  ist auch "Eigene" frei belegbar. Änderungen werden sofort gespeichert und
  wirken beim nächsten Öffnen der Start-Seite.

**Noch offen:** Schrittzähler (ACTIVITY_RECOGNITION, siehe Abschnitt 56)
und Stellplatz-POIs für Wohnmobilisten.

**Zu prüfen auf dem Gerät:** Höhe der flachen Kacheln (80/88/96 dp, feste
Näherungswerte) bei großer Systemschrift; Lesbarkeit der dreizeiligen
Kartenvorwahl; Ziehen der Einträge im ReorderableListView innerhalb der
scrollenden Einstellungsseite.

**Betroffene/neue Dateien:**
- `lib/models/start_grid_columns.dart` (NEU)
- `lib/ui/start_page.dart` (flache Kacheln, ein-/zweispaltiges Layout)
- `lib/ui/settings_page.dart` (Unterreiter "Start", vier statt drei Tabs)
- `lib/services/app_preferences.dart` (`startGridColumns`, Slots ohne
  Duplikate)

## 58. Kompass-Seite: nur noch Rose und Kurs

Höhe, Luftdruck (samt Trend) und Position stehen seit der Start-Seite
(Abschnitt 56/57) dort und entfallen auf der Kompass-Seite. Übrig bleiben
die Statuszeile (Genauigkeits-Badge, Chip "Kompass gestört", Buttons
"Höhe kalibrieren" und "Kompass kalibrieren", Mess-Impuls), die
Kompassrose und darunter die Kursangabe samt Genauigkeit ("Kurs: 87°").

**Layout:** Die Rose nimmt den gesamten Platz zwischen Statuszeile und
Kursangabe ein (quadratisch, mindestens 120, höchstens 600 dp, Seitenrand
16 dp) - bisher begrenzten 80 % der Breite und 48 % der Höhe sie auf
maximal 360 dp (Abschnitt 28). Die Kursangabe steht unter der Rose in einer
FittedBox(scaleDown), damit sie bei großer Systemschrift in der Breite
bleibt.

**Dienste laufen unverändert weiter**, auch wenn ihre Werte hier nicht
mehr angezeigt werden: GPS-Höhe und Barometer (für die Missweisung =
Kurs auf geografisch Nord, Abschnitt 41, für die Höhenkalibrierung,
Abschnitt 54, und für die Höhenmeldung an den Luftdruck-Trend, Abschnitt
47). Der Dialog "Höhe kalibrieren" zeigt weiterhin die aktuell angezeigte
Höhe, NN-Korrektur und manuellen Versatz.

**Start-Seite (Korrektur zu Abschnitt 56):** Nur die Tempo-Kachel (-> Tacho)
und die Kompass-Kachel (-> Kompass) öffnen eine Vollansicht. Höhe,
Luftdruck und Position haben keine eigene Seite mehr und reagieren nicht
auf Antippen.

**Betroffene Dateien:** `lib/ui/compass_page.dart`, `lib/ui/start_page.dart`.

## 59. Missweisung auf der Kompass-Seite

Unter der Kursangabe steht jetzt die für den Standort ermittelte
Missweisung (Deklination), z. B. "Missweisung: 3,4° O". Das ist genau der
Wert, den `CompassService` auf den Magnetkurs addiert, damit "Kurs" auf
geografisch Nord bezogen ist (Abschnitt 41): "O" = Ostmissweisung
(magnetisch Nord liegt östlich von geografisch Nord, der Wert wird
addiert), "W" = Westmissweisung. Solange noch kein Standort bekannt ist,
steht dort "unbekannt (magnetischer Kurs)" - dann ist der angezeigte Kurs
noch nicht korrigiert.

Der Wert stammt aus Androids `GeomagneticField` (offline, Weltmagnetmodell)
für Standort, Höhe und aktuelles Datum und wird bei einer Ortsänderung von
mehr als ca. 0,25° neu bestimmt. Er ist ein Modellwert: Er gibt die
großräumige Abweichung an (Genauigkeit typischerweise etwa ein halbes Grad),
nicht örtliche Störungen durch Metall oder Gestein.

**Betroffene Dateien:** `lib/services/compass_service.dart` (Getter
`declinationDegrees`), `lib/ui/compass_page.dart` (Anzeige, Neuzeichnen nach
der Ermittlung).

## 60. Seemarken als gleichberechtigtes Overlay ("Einblenden")

**Änderung:** Das Seemarken-Overlay (OpenSeaMap) ist kein eigener Schalter
mehr, sondern die vierte Alternative in der Overlay-Auswahl - neben Aus,
Wanderrouten und Radrouten. Die Auswahl heißt jetzt "Einblenden" statt
"Routen einblenden" (Karten-Button auf Track-Seite/Detailansicht und
Einstellungen -> Karten), und der Eintrag "Aus" beschreibt sich allgemein
("Nichts zusätzlich über der Karte einblenden."). Die Seemarken haben jetzt
auch eine eigene Quellenkarte in den Einstellungen und einen eigenen
Abschnitt in der Legende (wie die Routen-Overlays).

**Folge:** Die vier Alternativen schließen sich gegenseitig aus. Seemarken
und Wander-/Radrouten lassen sich nicht mehr gleichzeitig einblenden.

**Umsetzung:** `RouteOverlay` (`models/route_overlay.dart`) hat den neuen
Wert `seamarks` (Kachel-URL `tiles.openseamap.org/seamark/...`, höchste
native Zoomstufe 18, Quellenangabe "Seemarken: © OpenSeaMap-Mitwirkende").
Der Typname blieb aus Kompatibilitätsgründen "RouteOverlay"; fachlich ist es
das Overlay der Karte. `buildMapTileLayers` zeichnet Seemarken jetzt über
dieselbe Ebene wie die Routen (die eigene Seemarken-Ebene entfiel); der
Parameter `nauticalMode` ist ohne Wirkung und nur noch für ältere Aufrufer
(TrackPage, TrackDetailPage) vorhanden. `AppPreferences.mapNauticalMode`
ist nur noch eine abgeleitete Sicht (`routeOverlay == seamarks`),
`setMapNauticalMode` entfiel. Die Kartenvorwahl des Profils "Segeln" setzt
jetzt `RouteOverlay.seamarks` statt eines eigenen Seemarken-Wertes
(`UserProfile.nauticalOverlay` entfiel).

**Übernahme alter Einstellungen:** War der frühere Seemarken-Schalter
eingeschaltet und ist sonst kein Overlay gewählt, bleiben die Seemarken
sichtbar. War zusätzlich ein Routen-Overlay gewählt, bleibt dieses
erhalten. Der alte Schlüssel wird danach entfernt.

**Zu prüfen auf dem Gerät:** Seemarken-Kacheln und Quellenangabe unter der
Karte (Zoomstufen über 18 werden vergrößert statt leer dargestellt), die
Legende bei gewähltem Overlay "Seemarken".

**Betroffene Dateien:** `lib/models/route_overlay.dart`,
`lib/models/user_profile.dart`, `lib/services/app_preferences.dart`,
`lib/ui/settings_page.dart`, `lib/ui/widgets/map_tile_layers.dart`,
`lib/ui/widgets/map_style_button.dart`, `lib/ui/widgets/map_legend_button.dart`.

## 61. Start-Seite: Stillstand-Symbol im Tempo-Slot, Höhenkalibrierung im Höhen-Slot, Profil in der AppBar

**Statuszeile:** Auf der Start-Seite gibt es keine Statuszeile (Satellitenzahl,
Pause-Symbol) mehr; sie bleibt nur auf Tacho- und Kompass-Seite
(`HomeShell._tabsWithStatusBar`). Das Stillstand-/Bewegungs-Symbol sitzt
dafür in der Kopfzeile der **Tempo-Kachel**: orangefarbene Pause =
Stillstand erkannt, grünes Abspielen = in Bewegung, graues Symbol =
unbekannt. Die Regel ist dieselbe wie auf der Tacho-Seite (Bewegungssensor
UND GPS-Rohwert unter 8 km/h, `LiveDataService.stationary`). Die Satellitenzahl
wird auf der Start-Seite nicht mehr angezeigt.

**Höhenkalibrierung:** Der Button "Höhe kalibrieren" in der Statuszeile der
Kompass-Seite entfällt (dort wird keine Höhe mehr angezeigt, Abschnitt 58).
Stattdessen öffnet ein Antippen der **Höhen-Kachel** auf der Start-Seite den
Kalibrierdialog (Abschnitt 54); ein kleines Regler-Symbol in der Kopfzeile
der Kachel weist darauf hin. Inhalt und Wirkung des Dialogs sind unverändert
(bekannte Höhe eingeben, Versatz zur angezeigten Höhe wird gespeichert,
Zurücksetzen auch unter Einstellungen -> Erweitert). **Voraussetzung:** Die
Höhen-Kachel muss im gewählten Profil belegt sein (Einstellungen -> Start) -
im Standardprofil "Segeln" ist sie nicht belegt. Die Höhe, die die Start-Seite
anzeigt, wird jetzt auch an den Luftdruck-Trend gemeldet (Erkennung von
Höhenänderungen, Abschnitt 47), wie bisher von der Kompass-Seite.

**AppBar:** Neben dem Seitennamen steht, mit Gedankenstrich getrennt, das
gewählte Profil (Kurzname), z. B. "Tacho – Segeln" oder "Start – Rad / Moto".
Ohne gewähltes Profil steht nur der Seitenname. Der Titel bleibt einzeilig
und wird bei Platzmangel verkleinert (FittedBox) statt umzubrechen.

**Betroffene Dateien:** `lib/ui/start_page.dart`, `lib/services/live_data_service.dart`,
`lib/ui/compass_page.dart`, `lib/ui/home_shell.dart`, `lib/ui/settings_page.dart`
(Hinweistext zur Höhenkalibrierung).

## 62. Satelliten in der AppBar, neue Standardbelegung, "Reisen", Reiter-Reihenfolge, Berechtigungen

**Satellitenanzahl:** Immer sichtbar in der AppBar, links neben dem
Info-Button (`widgets/satellite_indicator.dart`, Farben wie bisher: grau =
keine aktuellen Daten, rot = 0, orange = 1-3, grün = ab 4). Die Statuszeile
unter der AppBar (nur Tacho und Kompass) zeigt dadurch nur noch das
Stillstand-/Bewegungs-Symbol (`AppStatusBar`), die Satellitenzahl dort
entfällt, um Doppelungen zu vermeiden. Im Karten-Vollbild der Track-Seite
(AppBar ausgeblendet, Abschnitt 58 ff.) ist auch die Satellitenzahl nicht
sichtbar.

**Standardbelegung der Slots** (`models/user_profile.dart`; gilt für alle,
die für ein Profil noch keine eigene Belegung gespeichert haben - eine schon
angepasste Belegung bleibt erhalten, "Standard wiederherstellen" in
Einstellungen -> Start übernimmt die neue):

| Profil | Slots (in dieser Reihenfolge) |
|---|---|
| Wandern | Kompass, Höhe, Luftdruck, Position, Kartenvorwahl |
| Segeln | Kompass, Kurs, Tempo, Position, Luftdruck, Kartenvorwahl |
| Rad / Moto | Tempo, Höhe, Kompass, Kurs, Luftdruck, Kartenvorwahl |
| Reisen | Tempo, Höhe, Kompass, Position, Luftdruck, Kartenvorwahl |
| Eigene | Tempo, Kurs, Höhe, Position, Luftdruck, Kartenvorwahl |

Die Kartenvorwahl des Profils "Eigene" ist die Standardkarte ohne Overlay
(früher hatte "Eigene" keine Kartenvorwahl).

**"Wohnmobil" heißt jetzt "Reisen"** (Name und Kurzname in Profil-Leiste,
AppBar-Titel und Einstellungen). Der interne Bezeichner `UserProfile.camper`
bleibt unverändert, damit die gespeicherte Profilwahl gültig bleibt.

**Einstellungen:** Der Reiter "Start" ist jetzt der erste (und damit der
beim Öffnen sichtbare), danach Anzeige, Karten, Erweitert.

**Info-Seite:** Neuer Abschnitt "Berechtigungen" mit allen im Manifest
angeforderten Berechtigungen (Standort, Vordergrunddienst für Standort,
Benachrichtigungen, WAKE_LOCK, Internet) samt Begründung sowie dem Hinweis,
welche Funktionen keine Berechtigung brauchen (Sensoren, GPX-Import und
-Export) und dass kein Standortzugriff im Hintergrund angefordert wird. Die
Liste steht als Konstante `_permissions` in `info_page.dart` und muss bei
Änderungen an der `AndroidManifest.xml` mitgepflegt werden.

**Betroffene/neue Dateien:** `lib/ui/widgets/satellite_indicator.dart` (NEU),
`lib/ui/widgets/app_status_bar.dart`, `lib/ui/home_shell.dart`,
`lib/models/user_profile.dart`, `lib/ui/settings_page.dart`,
`lib/ui/info_page.dart`.

## 63. Statuszeile entfällt

Die Statuszeile unter der AppBar (`widgets/app_status_bar.dart`, bisher auf
Tacho- und Kompass-Seite mit dem Stillstand-/Bewegungs-Symbol) entfällt
ganz; ihr Platz gehört jetzt den Seiten. HomeShell setzt `_buildPage(...)`
direkt als `body` des Scaffolds. Die Satellitenzahl steht immer sichtbar in
der AppBar (Abschnitt 62), das Stillstand-Symbol in der Tempo-Kachel der
Start-Seite (Abschnitt 61). Tacho- und Kompass-Seite zeigen es nicht mehr.
`widgets/app_status_bar.dart` wird nicht mehr verwendet und kann gelöscht
werden (`DeviceStatusService.displayStationary` und
`reportSpeedPageStationary` bleiben bestehen, werden aber nur noch intern
genutzt).

**Betroffene Dateien:** `lib/ui/home_shell.dart`.

## 64. Aufzeichnungs-Indikator auf der Start-Seite

Unten in der Profil-Leiste der Start-Seite (links unten) zeigt
`widgets/recording_indicator.dart` den Zustand einer Track-Aufzeichnung:
- **Aufzeichnung läuft:** sanft blinkender roter Punkt, darunter "Aufnahme".
- **Pausiert** (manuell oder automatisch bei Stillstand): oranges
  Pause-Symbol, darunter "Pausiert".
- **Keine Aufzeichnung:** nichts, das Widget belegt dann keinen Platz.

Antippen öffnet die Track-Seite. Das Widget hört direkt auf
`TrackRecordingService.updates`, baut sich aber nur bei einem
Zustandswechsel neu auf (nicht bei jedem neuen Punkt); die Blink-Animation
läuft nur während aktiver Aufzeichnung. `StartPage` bekommt dafür den von
HomeShell gehaltenen `TrackRecordingService` als neuen Parameter
`recordingService`. Die Leiste ist dazu in eine Spalte aus Profil-Buttons
(scrollbar wie bisher) und dem Indikator darunter umgebaut, 80 dp breit.

**Zu prüfen auf dem Gerät:** Lesbarkeit des Blinkens im Freien; Verhalten der
Leiste auf sehr niedrigen Displays (Buttons scrollen, der Indikator bleibt
unten stehen).

**Betroffene/neue Dateien:** `lib/ui/widgets/recording_indicator.dart` (NEU),
`lib/ui/start_page.dart`, `lib/ui/home_shell.dart`.

## 65. Aufzeichnungs-Indikator mit Warnung bei Unterbrechung

Der rote Punkt (Abschnitt 64) erscheint nur noch, wenn die Aufzeichnung
tatsächlich arbeitet. Besteht der Zustand "aufzeichnend", der Dienst liefert
aber nicht mehr, zeigt der Indikator stattdessen ein schneller blinkendes
**rotes Warn-Dreieck mit "Unterbrochen"** (Tooltip nennt den Grund).

**Prüfung (`TrackRecordingService.interruptionReason`):** null = in Ordnung.
Eine Unterbrechung wird gemeldet, wenn
- der Positions-Stream ausgefallen ist und Neustart-Versuche laufen
  (`_consecutiveStreamFailures > 0`, Abschnitt 30.4; bleibt bis zum ersten
  erfolgreich empfangenen Punkt bestehen),
- der Stream nicht aktiv ist (nach einer Schonfrist von 5 s nach
  Start/Fortsetzen),
- oder bei AKTIVER Aufzeichnung länger als 30 s keine Position eintrifft
  (auch vor dem ersten GPS-Fix, z. B. im Gebäude). Bei Stillstand pausiert die
  automatische Pause nach ca. 13 s, 30 s sind also deutlich mehr als ein
  normaler Halt.

Bei einer MANUELLEN Pause wird nichts geprüft (es wird kein Stream
gebraucht), bei einer AUTOMATISCHEN Pause nur, ob der Stream noch läuft (im
Stand kommen wegen des distanceFilters keine Punkte). Der Service prüft im
Sekundentakt (der vorhandene Timer der Stillstandserkennung), meldet
Änderungen über `updates` und schreibt sie ins Diagnose-Protokoll
("WARNUNG: ..." bzw. "Aufzeichnung wieder in Ordnung", nur Debug-Builds).
Das Widget hört auf `updates` und prüft zusätzlich alle 2 s selbst, weil
eine Unterbrechung durch AUSBLEIBENDE Daten entsteht.

**Grenzen:** Geprüft wird, ob Positionen im Dart-Code ankommen - ob der
native Foreground-Service samt Benachrichtigung läuft, lässt sich von Dart
aus nicht abfragen. Fällt eine automatische Pause durch GPS-Verlust (Tunnel)
zusammen mit einer Pause, zeigt der Indikator weiterhin "Pausiert", solange
der Stream selbst läuft. Stirbt der gesamte App-Prozess, kann der Indikator
naturgemäß nichts anzeigen - dafür gibt es die Wiederherstellung über den
Checkpoint (Abschnitt 30.4).

**Zu prüfen auf dem Gerät:** Warnung z. B. durch Ausschalten des
Standortdienstes während der Aufzeichnung (Stream-Fehler) und durch Start im
Gebäude ohne Fix.

**Betroffene Dateien:** `lib/services/track_recording_service.dart`
(`interruptionReason`, Prüfung im Sekundentakt),
`lib/ui/widgets/recording_indicator.dart`.

## 66. Berechtigungstexte in einfacher Sprache

Die Texte im Abschnitt "Berechtigungen" der Info-Seite (Abschnitt 62) sind
jetzt für Laien formuliert: kurze Erklärung, wofür onTour die jeweilige
Erlaubnis braucht und was ohne sie passiert, ohne technische Namen. Die
fünf Einträge heißen: Standort, Aufzeichnung im Hintergrund,
Benachrichtigungen, Gerät wach halten, Internet. Ein Abschlusstext nennt,
was keine Erlaubnis braucht (Sensoren, Dateien speichern/teilen) und dass
onTour nicht auf Kontakte, Fotos, Kamera, Mikrofon oder Nachrichten
zugreift.

Die technischen Namen (z. B. ACCESS_FINE_LOCATION, FOREGROUND_SERVICE_LOCATION,
POST_NOTIFICATIONS, WAKE_LOCK, INTERNET) stehen nicht mehr in der App. Sie
bleiben in der `AndroidManifest.xml` und sind für die Angaben in der Play
Console nötig - dort können die Begründungen aus diesen Texten
sinngemäß übernommen werden.

**Pflege:** Der Satz "Deine Strecken und Positionen bleiben auf deinem
Gerät" gilt für den heutigen Stand der App und muss überprüft werden, sobald
eine Funktion Daten hochlädt. Die Liste `_permissions` in `info_page.dart`
muss bei Änderungen am Manifest mitgepflegt werden.

**Betroffene Dateien:** `lib/ui/info_page.dart`.

## 67. Eigenes Symbol für das Profil "Eigene"

Das Profil "Eigene" nutzte dasselbe Regler-Symbol (`Icons.tune`) wie der
Hinweis "Höhe kalibrieren" in der Höhen-Kachel der Start-Seite. Es hat jetzt
ein eigenes Symbol (`Icons.person`, Person). Das Symbol erscheint in der
Profil-Leiste der Start-Seite und in den Profil-Chips unter Einstellungen ->
Start; das Regler-Symbol bleibt der Kalibrierung vorbehalten.

**Betroffene Dateien:** `lib/models/user_profile.dart`.

## 68. Profil "Segler": Track-Auswertung in Seemeilen und Knoten

Im Profil "Segler" erfolgt die Auswertung von Tracks in **Seemeilen (sm)**
und **Knoten (kn)** statt in km und km/h (1 sm = 1852 m, 1 m/s = 1,94384 kn).
Das gilt für:
- Statuskarte der laufenden Aufzeichnung (Distanz, Ø-Tempo) und die
  Momentan-Geschwindigkeit auf dem Details-Tab,
- Liste gespeicherter Tracks, Statuskarte der Detailansicht (Distanz,
  Ø-Tempo), den Wiederherstellungs-Dialog nach unerwartetem Beenden,
- die Profil-Diagramme (Geschwindigkeitsprofil in kn, x-Achse in sm) auf
  beiden Details-Tabs,
- die Luftlinie zum Ziel auf der Track-Karte.

**Darstellung:** Strecken unter 100 m in Metern, darunter in sm - unter
1 sm mit zwei Nachkommastellen ("0,45 sm"), ab 1 sm mit einer ("12,3 sm").
Geschwindigkeiten mit einer Nachkommastelle ("5,8 kn").

**Umsetzung:** `TrackFormatter.formatDistance/formatAverageSpeed` und neu
`formatSpeed` haben den Parameter `nautical`. `AppPreferences.nauticalTrackUnits`
ist wahr im Profil "Segler" und wird von TrackPage, TrackDetailPage und den
Diagrammen (`TrackProfileCharts.nautical`, `ProfileChart.distanceUnit`)
verwendet. Gespeichert wird weiterhin in Metern und m/s - die Umstellung
wirkt nur auf die Anzeige und gilt beim Wechsel des Profils sofort, auch für
zuvor in einem anderen Profil aufgezeichnete Tracks. Höhe, Höhenänderung und
Steigung bleiben in m bzw. %.

**Nebenwirkung:** Die Momentan-Geschwindigkeit auf dem Details-Tab der
Track-Seite hat jetzt (wie die übrigen Werte) ein Komma statt eines Punktes
als Dezimaltrenner.

**Nicht umgestellt:** Die Tempo-Einheit der Tacho-Seite und der Start-Seite
(eigene Einstellung je Profil, Abschnitt 56) und der GPX-Export (Standard).

**Betroffene Dateien:** `lib/util/track_formatter.dart`,
`lib/services/app_preferences.dart`, `lib/ui/track_page.dart`,
`lib/ui/track_detail_page.dart`, `lib/ui/widgets/track_profile_charts.dart`,
`lib/ui/widgets/profile_chart.dart`.

## 69. Info-Seite: Umrechnungsfaktoren

Neuer, kleiner Abschnitt "Umrechnungsfaktoren" auf der Info-Seite (unter
"Berechtigungen", vor "Kartenmaterial"). Er nennt, womit onTour Messwerte
für die Anzeige umrechnet - intern wird alles in Metern und Metern pro
Sekunde geführt:

| Größe | Faktor |
|---|---|
| 1 m/s | = 3,6 km/h |
| 1 m/s | = 1,94384 kn |
| 1 m/s | = 2,23694 mph |
| 1 Seemeile (sm) | = 1852 m = 1,852 km |
| 1 Knoten (kn) | = 1 sm pro Stunde |
| 1 Meile (mi, für mph) | = 1.609,344 m |
| 1 Grad (°) | = 60 Minuten (') = 3600 Sekunden (") |

Die Zahlen werden nicht von Hand in den Text geschrieben, sondern aus den
Konstanten gebildet, mit denen die App tatsächlich rechnet
(`SpeedUnit.fromMetersPerSecond`, `TrackFormatter.metersPerNauticalMile`) -
Anzeige und Berechnung können nicht auseinanderlaufen. Ändert sich ein
Faktor im Code, ändert sich die Anzeige mit. (Meile und Grad/Minuten/Sekunden
stehen als feste Texte, sie sind im Code ebenfalls als Zahlen eingetragen.)

**Betroffene Dateien:** `lib/ui/info_page.dart`.

## 70. Hinweis "keine Navigation" mit Bestätigungspflicht

**Zweck:** onTour ist nicht zur Navigation gedacht und nicht dafür geeignet.
Das stellt ein eindeutiger Hinweis klar, der bei jedem Start erscheint, bis
der Nutzer ausdrücklich bestätigt, ihn gelesen und verstanden zu haben.

**Ablauf:**
- `HomeShell` zeigt den Hinweis nach dem ersten Aufbau der Oberfläche
  (`showNavigationNoticeDialog`, `ui/navigation_notice_dialog.dart`), solange
  `AppPreferences.navigationNoticeAccepted` falsch ist. Das ist vor dem
  ersten Standort-Abfragen der Fall: Auf der Start-Seite läuft ohne gewähltes
  Profil noch kein Sensor.
- Der Dialog lässt sich nicht wegtippen (`barrierDismissible: false`) und
  nicht mit der Zurück-Taste schließen (`PopScope`). Er enthält vier kurze
  Absätze, eine Checkbox "Ich habe diesen Hinweis gelesen und verstanden: ..."
  und zwei Knöpfe: "Verstanden" (erst nach Anhaken aktiv) und "App beenden".
- "Verstanden" speichert die Bestätigung (Version des Hinweises und Zeitpunkt,
  `AppPreferences.acceptNavigationNotice`). Danach erscheint der Dialog nicht
  mehr. Wer die App nur beendet, sieht ihn beim nächsten Start wieder - auch
  bei erhaltenem App-Prozess (persistente Engine, Abschnitt 21), weil der
  Dialog dann noch offen ist.
- Auf der Info-Seite steht derselbe Text jederzeit nachlesbar in einem
  Hinweiskasten ganz oben.

**Wortlaut:** zentral in `util/navigation_notice.dart` (`NavigationNotice`),
damit Dialog und Info-Seite immer dasselbe sagen. Inhalt: kein
Navigationsgerät; Anzeigen können ungenau, verzögert, falsch oder ausgefallen
sein (auch Luftlinie/Richtung zum Ziel ist keine Routenführung); Karten und
Seemarken stammen von Dritten und sind nicht amtlich; nicht darauf verlassen,
wenn Sicherheit, Gesundheit oder Eigentum betroffen sind, nicht bedienen
beim Führen eines Fahrzeugs oder Bootes.

**Erneut bestätigen lassen:** Ändert sich der Inhalt wesentlich,
`AppPreferences.currentNavigationNoticeVersion` erhöhen - dann muss jeder
Nutzer den Hinweis erneut bestätigen. Nach dem Update auf diese Version
sehen ihn alle bestehenden Nutzer einmal.

**Rechtlicher Hinweis:** Der Wortlaut ist ein Entwurf, keine Rechtsberatung.
Er sollte vor der Veröffentlichung von einer fachkundigen Person geprüft
werden. Eine inhaltlich passende Aussage gehört außerdem in die
Store-Beschreibung.

**Betroffene/neue Dateien:** `lib/util/navigation_notice.dart` (NEU),
`lib/ui/navigation_notice_dialog.dart` (NEU), `lib/services/app_preferences.dart`,
`lib/ui/home_shell.dart`, `lib/ui/info_page.dart`.
