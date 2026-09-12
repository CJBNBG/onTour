package de.clausjbauer.ontour

import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Stellt die Anzahl der aktuell für den GPS-Fix verwendeten Satelliten über
 * einen eigenen EventChannel bereit (siehe services/satellite_service.dart,
 * README Abschnitt 3) - weder das geolocator-Paket noch iOS/CoreLocation
 * liefern diese Information, unter Android ist sie aber über die
 * GNSS-Status-API (LocationManager.registerGnssStatusCallback, API Level
 * 24+) zugänglich.
 *
 * WICHTIG: Der Kanalname MUSS exakt mit dem Dart-seitigen Namen in
 * satellite_service.dart übereinstimmen ("ontour/gnss_satellite_count") -
 * bei einer eventuell abweichenden applicationId/Paketstruktur muss auch
 * die "package"-Zeile oben sowie der Dateipfad entsprechend angepasst
 * werden (siehe README Abschnitt 1/18).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ontour/gnss_satellite_count"
    private var eventSink: EventChannel.EventSink? = null
    private var gnssStatusCallback: GnssStatus.Callback? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    startGnssStatusUpdates()
                }

                override fun onCancel(arguments: Any?) {
                    stopGnssStatusUpdates()
                    eventSink = null
                }
            }
        )
    }

    private fun startGnssStatusUpdates() {
        // GNSS-Status-API erst ab API 24 (Android 7.0) verfügbar - auf
        // älteren Geräten bleibt der Stream einfach leer, die Dart-Seite
        // (SatelliteService) zeigt dafür bereits konsequent "nicht
        // verfügbar" statt eines Fehlers an.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return

        val locationManager =
            getSystemService(LOCATION_SERVICE) as? LocationManager ?: return

        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                var usedInFixCount = 0
                for (i in 0 until status.satelliteCount) {
                    if (status.usedInFix(i)) {
                        usedInFixCount++
                    }
                }
                eventSink?.success(usedInFixCount)
            }
        }
        gnssStatusCallback = callback

        try {
            locationManager.registerGnssStatusCallback(callback)
        } catch (e: SecurityException) {
            // Fehlende Standort-Berechtigung - SpeedService fragt sie
            // bereits Dart-seitig ab; hier einfach keine Werte liefern,
            // statt abzustürzen.
        }
    }

    private fun stopGnssStatusUpdates() {
        val locationManager = getSystemService(LOCATION_SERVICE) as? LocationManager
        gnssStatusCallback?.let { locationManager?.unregisterGnssStatusCallback(it) }
        gnssStatusCallback = null
    }

    override fun cleanUpFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        stopGnssStatusUpdates()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
