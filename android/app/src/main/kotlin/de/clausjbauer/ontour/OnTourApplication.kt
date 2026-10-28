package de.clausjbauer.ontour

import android.app.Application
import android.hardware.GeomagneticField
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * NEU (siehe README Abschnitt 21): Erzeugt beim Start des Android-Prozesses
 * - also VOR jeder Activity - eine einzige, app-weite [FlutterEngine] und
 * legt sie im [FlutterEngineCache] ab. [MainActivity] verwendet
 * ausschließlich DIESE Engine ([MainActivity.provideFlutterEngine]) statt,
 * wie im Flutter-Standardverhalten üblich, bei jedem Activity-Start eine
 * neue zu erzeugen und beim Beenden der Activity wieder zu zerstören.
 *
 * GRUND: Nur so übersteht eine laufende Track-Aufzeichnung (samt aller
 * bereits gesammelten Punkte, der aktuellen Distanz und Dauer - all das
 * lebt ausschließlich im Dart-Heap von TrackRecordingService, siehe dort)
 * ein Entfernen der App aus der Liste der zuletzt verwendeten Apps
 * ("Wischen"/Swipe-to-close). OHNE diese Änderung würde Android beim
 * Entfernen der App-Kachel MainActivity UND die zu ihr gehörende
 * (Standard-)FlutterEngine zerstören - der komplette Dart-Zustand ginge
 * verloren, selbst wenn der zugrunde liegende native Android-Foreground-
 * Service (siehe TrackRecordingService, README Abschnitt 19) unbeeindruckt
 * weiterläuft, seine Benachrichtigung weiter anzeigt und GPS-Punkte
 * weiterhin nativ empfängt: Ohne eine lebendige Dart-Engine kommen diese
 * Punkte nirgends mehr an, die Aufzeichnung "friert" dadurch faktisch ein,
 * obwohl sie äußerlich (Benachrichtigung) noch aktiv wirkt.
 *
 * Erweitert bewusst die normale `android.app.Application` - die früher
 * dafür übliche `io.flutter.app.FlutterApplication` ist seit Flutter
 * 3.29 nur noch eine leere, als veraltet markierte Hülle ohne
 * Zusatzfunktion (die Engine-Initialisierung läuft inzwischen über einen
 * automatisch eingebundenen `ContentProvider`); Flutters eigene
 * Dokumentation empfiehlt seitdem ausdrücklich, direkt von
 * `Application` zu erben. Falls dein Projekt bereits eine eigene
 * Application-Klasse hat, füge den Inhalt von [onCreate] dort ein, statt
 * diese Datei zusätzlich zu verwenden.
 *
 * WICHTIG: `FlutterEngine(context)` registriert beim Erzeugen bereits
 * automatisch ALLE Plugins (siehe Flutter-Dokumentation zu `FlutterEngine`
 * - "A new FlutterEngine automatically attaches all plugins") - ein
 * zusätzlicher, manueller Aufruf von
 * `GeneratedPluginRegistrant.registerWith(...)` ist hier bewusst NICHT
 * nötig und würde die Plugins doppelt registrieren.
 *
 * NEU (siehe README Abschnitt 22): Registriert zusätzlich den
 * MethodChannel für die Pause-Erinnerung (Dart-Seite: siehe
 * TrackRecordingService) - bewusst HIER und nicht in MainActivity, siehe
 * [setupAutoPauseReminderChannel].
 */
class OnTourApplication : Application() {

    companion object {
        /** Eindeutige ID, unter der die Engine im FlutterEngineCache
         *  abgelegt wird - siehe MainActivity.provideFlutterEngine. */
        const val ENGINE_ID = "ontour_persistent_engine"

        /** Name des MethodChannel für die Pause-Erinnerung - muss exakt
         *  mit dem Dart-seitigen Namen in TrackRecordingService
         *  übereinstimmen. */
        private const val CHANNEL_AUTO_PAUSE_REMINDER = "ontour/auto_pause_reminder"

        /** Name des MethodChannel für den Sprung zum Track-Tab (siehe
         *  README Abschnitt 23) - muss exakt mit dem Dart-seitigen Namen
         *  in HomeShell übereinstimmen. */
        private const val CHANNEL_NAVIGATION = "ontour/navigation"

        /** Name des MethodChannel fuer die Missweisung (Deklination) des
         *  Magnetkompasses - muss exakt mit dem Dart-seitigen Namen in
         *  CompassService uebereinstimmen. */
        private const val CHANNEL_GEOMAGNETIC = "ontour/geomagnetic"
    }

    override fun onCreate() {
        super.onCreate()

        val flutterEngine = FlutterEngine(this)

        // Führt main() aus lib/main.dart aus - inkl. der dortigen
        // Initialisierung von AppPreferences, Silbentrennung und
        // Datumsformatierung (siehe main.dart) - bereits hier beim
        // Prozessstart, nicht erst beim Öffnen der ersten Activity. Das
        // ist beabsichtigt und unschädlich: main() läuft dadurch nur
        // zeitlich etwas früher, nicht öfter.
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)

        setupAutoPauseReminderChannel(flutterEngine)
        setupNavigationChannel(flutterEngine)
        setupGeomagneticChannel(flutterEngine)
    }

    /**
     * NEU (siehe README Abschnitt 22): Nimmt vom Dart-seitigen
     * TrackRecordingService "schedule"/"cancel"-Aufrufe entgegen und
     * reicht sie an [AutoPauseReminderScheduler] weiter, der den
     * eigentlichen `AlarmManager`-Alarm setzt bzw. storniert.
     *
     * WICHTIG, warum das hier in OnTourApplication und NICHT in
     * MainActivity registriert wird: TrackRecordingService kann eine
     * Pause (und damit einen Schedule-/Cancel-Aufruf) JEDERZEIT auslösen
     * - auch dann, wenn gerade GAR KEINE Activity existiert (z. B. weil
     * die App aus den zuletzt verwendeten Apps entfernt wurde, siehe
     * Abschnitt 21). Ein in MainActivity registrierter Handler wäre in
     * diesem Fall nicht erreichbar bzw. müsste einen möglicherweise
     * bereits zerstörten Activity-Context verwenden. Der hier
     * verwendete `applicationContext` bleibt dagegen so lange gültig wie
     * der Android-Prozess selbst - und genau dieser Prozess läuft dank
     * des in Abschnitt 21 beschriebenen Foreground-Service-Zusammenspiels
     * während einer aktiven Aufzeichnung durchgehend weiter.
     */
    private fun setupAutoPauseReminderChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_AUTO_PAUSE_REMINDER)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val minutes = call.argument<Int>("delayMinutes")
                        if (minutes == null || minutes <= 0) {
                            result.error(
                                "invalid_argument",
                                "delayMinutes fehlt oder ist ungültig",
                                null,
                            )
                        } else {
                            AutoPauseReminderScheduler.schedule(applicationContext, minutes)
                            result.success(null)
                        }
                    }
                    "cancel" -> {
                        AutoPauseReminderScheduler.cancel(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * NEU (siehe README Abschnitt 23): Beantwortet Dart-seitige Anfragen
     * (HomeShell), ob gerade ein "zum Track-Tab wechseln"-Wunsch vorliegt
     * (siehe [PendingNavigation], gesetzt von MainActivity beim Auswerten
     * des Benachrichtigungs-Intents) - und setzt diesen dabei zurück,
     * damit er nicht bei einem späteren, unabhängigen App-Start erneut
     * ausgelöst wird.
     */
    private fun setupNavigationChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAVIGATION)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingOpenTrackTab" -> {
                        val pending = PendingNavigation.openTrackTab
                        PendingNavigation.openTrackTab = false
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Liefert auf Anfrage von CompassService die Missweisung (Deklination)
     * fuer einen Standort in Grad (Android `GeomagneticField`, offline) -
     * damit der Magnetkompass auf geografisch Nord korrigiert werden kann.
     * Positiv, wenn magnetisch Nord oestlich von geografisch Nord liegt.
     */
    private fun setupGeomagneticChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_GEOMAGNETIC)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "declination" -> {
                        val lat = call.argument<Double>("latitude")
                        val lon = call.argument<Double>("longitude")
                        val alt = call.argument<Double>("altitude") ?: 0.0
                        if (lat == null || lon == null) {
                            result.error("invalid_argument", "latitude/longitude fehlen", null)
                        } else {
                            val field = GeomagneticField(
                                lat.toFloat(),
                                lon.toFloat(),
                                alt.toFloat(),
                                System.currentTimeMillis(),
                            )
                            result.success(field.declination.toDouble())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
