package de.clausjbauer.ontour

import android.content.Context
import android.content.Intent
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel

/**
 * Haupt-Activity von onTour.
 *
 * AUFGABE 1 - Satellitenanzahl (siehe README Abschnitt 3): registriert
 * einen EventChannel ("ontour/gnss_satellite_count"), der die Anzahl der
 * für den aktuellen Fix verwendeten Satelliten liefert (Android GNSS-
 * Status-API, `LocationManager.registerGnssStatusCallback`, ab API 24) -
 * weder `geolocator` noch iOS/CoreLocation stellen das bereit.
 *
 * AUFGABE 2 - NEU, persistente FlutterEngine (siehe README Abschnitt 21):
 * Damit eine laufende Track-Aufzeichnung ein Entfernen der App aus der
 * Liste der zuletzt verwendeten Apps ("Wischen"/Swipe) übersteht, wird
 * hier NICHT (wie im Flutter-Standardverhalten) bei jedem Start eine neue
 * FlutterEngine erzeugt. Stattdessen wird IMMER die eine, bereits in
 * OnTourApplication.onCreate() vorab gestartete und im FlutterEngineCache
 * abgelegte Engine wiederverwendet ([provideFlutterEngine]) und beim
 * Zerstören dieser Activity NICHT mit zerstört ([shouldDestroyEngineWithHost],
 * [cleanUpFlutterEngine]). Der zugrunde liegende Dart-Isolate - und damit
 * der komplette App-Zustand, inklusive TrackRecordingService mit allen
 * bereits gesammelten Punkten - lebt dadurch unabhängig von dieser
 * Activity weiter, solange der Android-Prozess selbst am Leben bleibt.
 * Genau das stellt der bereits vorhandene Foreground-Service während
 * einer aktiven Aufzeichnung sicher (siehe TrackRecordingService, README
 * Abschnitt 19): Android beendet Prozesse mit einem laufenden Foreground-
 * Service unter normalem Speicherdruck praktisch nie, unabhängig davon,
 * ob gerade eine Activity dafür existiert.
 *
 * WICHTIG: Diese Datei ersetzt die bisherige `MainActivity.kt` 1:1 (siehe
 * README Abschnitt 3 für den generellen Kopiervorgang). Falls deine
 * bisherige Version über die hier gezeigte GNSS-Logik hinaus eigene
 * Ergänzungen enthielt, übertrage diese zusätzlich in die drei neuen
 * Override-Methoden [provideFlutterEngine], [shouldDestroyEngineWithHost]
 * und [cleanUpFlutterEngine] bzw. in [configureFlutterEngine].
 *
 * AUFGABE 3 - NEU, Sprung zum Track-Tab (siehe README Abschnitt 23):
 * Wird die App über die Erinnerungs-Benachrichtigung einer anhaltend
 * pausierten Aufzeichnung geöffnet (siehe Abschnitt 22,
 * AutoPauseReminderReceiver), trägt der zugehörige Intent das Extra
 * [EXTRA_OPEN_TRACK_TAB]. [handleIntent] wertet das sowohl in [onCreate]
 * (Activity existierte noch nicht, z. B. nach einem Wischen aus den
 * zuletzt verwendeten Apps) als auch in [onNewIntent] (Activity existiert
 * bereits, wird dank `singleTask`-Startmodus - siehe AndroidManifest.xml -
 * lediglich in den Vordergrund geholt) aus und merkt sich das Ergebnis in
 * [PendingNavigation] - von dort holt HomeShell es sich per MethodChannel
 * ab (siehe dortiger Kommentar für die Begründung dieses "Pull"-Ansatzes).
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** Intent-Extra-Schlüssel - muss exakt mit dem in
         *  AutoPauseReminderReceiver.kt verwendeten Namen übereinstimmen. */
        const val EXTRA_OPEN_TRACK_TAB = "open_track_tab"
    }

    private var gnssStatusCallback: GnssStatus.Callback? = null
    private var locationManager: LocationManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Wichtig bei singleTask-Activities: den NEUEN Intent als
        // "aktuellen" Intent hinterlegen, falls später (z. B. bei einer
        // Konfigurationsänderung) erneut über getIntent() darauf
        // zugegriffen wird.
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_OPEN_TRACK_TAB, false) == true) {
            PendingNavigation.openTrackTab = true
            // Verhindert, dass ein erneutes Auswerten desselben Intents
            // (z. B. nach einer Konfigurationsänderung wie Rotation, auch
            // wenn diese App laut README nur Hochkant unterstützt) den
            // Navigationswunsch fälschlich ein zweites Mal auslöst.
            intent.removeExtra(EXTRA_OPEN_TRACK_TAB)
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Liefert IMMER die eine, app-weite Engine aus OnTourApplication -
        // ohne diesen Override würde FlutterActivity bei jedem (Neu-)
        // Start eine EIGENE, frische Engine erzeugen, wodurch der gesamte
        // Dart-Zustand (inkl. einer laufenden Aufzeichnung) beim
        // Wiederöffnen nach einem Wischen aus den zuletzt verwendeten
        // Apps verloren ginge (siehe Klassenkommentar).
        return FlutterEngineCache.getInstance().get(OnTourApplication.ENGINE_ID)
            // Sicherheitsnetz, sollte praktisch nie eintreten (nur falls
            // OnTourApplication aus irgendeinem Grund nicht korrekt als
            // Application-Klasse registriert wurde, siehe README
            // Abschnitt 21) - verhindert zumindest einen Absturz.
            ?: super.provideFlutterEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Verhindert, dass die (von OnTourApplication verwaltete,
        // app-weit geteilte) Engine zerstört wird, sobald DIESE Activity
        // zerstört wird - z. B. wenn der Nutzer die App aus den zuletzt
        // verwendeten Apps entfernt. Siehe Klassenkommentar.
        return false
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Bewusst KEIN super-Aufruf und keine eigene Aufräumlogik: Die
        // Standardimplementierung geht davon aus, dass DIESE Activity die
        // Engine besitzt und beim Trennen aufräumen muss - hier ist das
        // Gegenteil gewollt (siehe shouldDestroyEngineWithHost).
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ontour/gnss_satellite_count")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startGnssStatusUpdates(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopGnssStatusUpdates()
                }
            })
    }

    private fun startGnssStatusUpdates(events: EventChannel.EventSink) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            // GnssStatus.Callback benötigt mindestens API 24 - auf
            // älteren Geräten bleibt der Stream einfach leer (siehe
            // SatelliteService, das dann "nicht verfügbar" anzeigt).
            return
        }
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        locationManager = manager

        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                var usedInFixCount = 0
                for (i in 0 until status.satelliteCount) {
                    if (status.usedInFix(i)) usedInFixCount++
                }
                events.success(usedInFixCount)
            }
        }
        gnssStatusCallback = callback
        manager.registerGnssStatusCallback(callback, null)
    }

    private fun stopGnssStatusUpdates() {
        gnssStatusCallback?.let { locationManager?.unregisterGnssStatusCallback(it) }
        gnssStatusCallback = null
        locationManager = null
    }
}
