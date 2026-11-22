package de.clausjbauer.ontour

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * NEU (siehe README Abschnitt 72): Native Seite des Schrittzählers.
 *
 * Nutzt den Hardware-Sensor TYPE_STEP_COUNTER: Er liefert die Gesamtzahl der
 * Schritte seit dem letzten Neustart des Geräts (läuft auch im Ruhezustand in
 * der Sensor-Hardware weiter, solange er aktiviert ist). Alle Auswertung
 * (Tageszahl, Zählung während einer Aufzeichnung) passiert auf Dart-Seite
 * (StepCounterService) als Differenz zweier Zählerstände.
 *
 * Kanäle (beide in OnTourApplication registriert, damit sie unabhängig von
 * einer Activity funktionieren, siehe README Abschnitt 22):
 * - MethodChannel "ontour/steps": available, bootTime, midnightSnapshot,
 *   scheduleMidnight
 * - EventChannel "ontour/steps_stream": fortlaufende Zählerstände (Long)
 *
 * MITTERNACHTS-SNAPSHOT: Ein AlarmManager-Alarm (setAndAllowWhileIdle, keine
 * Sonderberechtigung nötig) liest kurz nach 00:00 Uhr den Zählerstand und legt
 * ihn in SharedPreferences ab. Damit lässt sich die Tageszahl auch dann exakt
 * bestimmen, wenn die App den ganzen Tag nicht geöffnet war.
 */
object StepCounterBridge {
    private const val CHANNEL = "ontour/steps"
    private const val EVENT_CHANNEL = "ontour/steps_stream"
    private const val PREFS = "ontour_steps"
    private const val KEY_DAY = "midnight_day"
    private const val KEY_COUNTER = "midnight_counter"
    private const val KEY_BOOT = "midnight_boot"
    private const val KEY_ENABLED = "midnight_enabled"
    private const val ALARM_REQUEST_CODE = 4713

    fun register(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext

        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(stepSensor(appContext) != null)
                    "bootTime" -> result.success(bootTimeMillis())
                    "midnightSnapshot" -> result.success(loadMidnightSnapshot(appContext))
                    "scheduleMidnight" -> {
                        // Merkt sich, dass der Nutzer die Funktion aktiviert hat -
                        // nur dann plant StepBootReceiver nach einem Neustart neu.
                        appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean(KEY_ENABLED, true).apply()
                        scheduleMidnight(appContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(StepStreamHandler(appContext))
    }

    private fun sensorManager(context: Context): SensorManager? =
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

    private fun stepSensor(context: Context): Sensor? =
        sensorManager(context)?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    /** Zeitpunkt des letzten Geräte-Starts (ms seit Epoche) - dient auf
     *  Dart-Seite zur Erkennung eines Neustarts (Zähler beginnt dann bei 0). */
    private fun bootTimeMillis(): Long = System.currentTimeMillis() - SystemClock.elapsedRealtime()

    // ==== Einmaliges Lesen (für den Mitternachts-Alarm) ====

    /**
     * Liest einmalig den aktuellen Zählerstand. Ruft [onResult] genau einmal
     * auf (null bei fehlendem Sensor, fehlender Berechtigung oder Zeitablauf).
     * Muss auf dem Main-Thread aufgerufen werden (BroadcastReceiver und
     * MethodChannel tun das).
     */
    fun readOnce(context: Context, timeoutMs: Long, onResult: (Long?) -> Unit) {
        val manager = sensorManager(context)
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (manager == null || sensor == null) {
            onResult(null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var done = false
        lateinit var listener: SensorEventListener
        val finish: (Long?) -> Unit = { value ->
            if (!done) {
                done = true
                manager.unregisterListener(listener)
                handler.removeCallbacksAndMessages(null)
                onResult(value)
            }
        }
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                finish(event.values[0].toLong())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        val registered = try {
            manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL, handler)
        } catch (e: SecurityException) {
            false
        }
        if (!registered) {
            finish(null)
            return
        }
        handler.postDelayed({ finish(null) }, timeoutMs)
    }

    // ==== Mitternachts-Snapshot ====

    private fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun saveMidnightSnapshot(context: Context, counter: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DAY, todayKey())
            .putLong(KEY_COUNTER, counter)
            .putLong(KEY_BOOT, bootTimeMillis())
            .apply()
    }

    private fun loadMidnightSnapshot(context: Context): Map<String, Any>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val day = prefs.getString(KEY_DAY, null) ?: return null
        if (!prefs.contains(KEY_COUNTER)) return null
        return mapOf(
            "day" to day,
            "counter" to prefs.getLong(KEY_COUNTER, 0L),
            "boot" to prefs.getLong(KEY_BOOT, 0L),
        )
    }

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    /** Plant den nächsten Mitternachts-Alarm (kurz nach 00:00 Uhr). Ein
     *  erneuter Aufruf ersetzt den bestehenden Alarm (fester Request-Code). */
    fun scheduleMidnight(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            next.timeInMillis,
            midnightPendingIntent(context),
        )
    }

    private fun midnightPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, StepMidnightReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ==== Live-Stream ====

    /**
     * Liefert zwei Sorten Meldungen als Map: {t: "c", v: Zählerstand} vom
     * Hardware-Zähler (TYPE_STEP_COUNTER - meldet auf vielen Geräten nur in
     * Paketen alle paar Sekunden) und {t: "s", v: 1} je Einzelschritt vom
     * Schritt-Detektor (TYPE_STEP_DETECTOR - sofort). Beide ohne Batching
     * (maxReportLatency 0). Der Detektor ist optional: fehlt er oder lässt er
     * sich nicht aktivieren, läuft nur der Zähler.
     */
    private class StepStreamHandler(private val context: Context) : EventChannel.StreamHandler {
        private var listener: SensorEventListener? = null
        private var detectorListener: SensorEventListener? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val manager = sensorManager(context)
            val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            if (manager == null || sensor == null) {
                events.error("unavailable", "Kein Schrittzähler-Sensor vorhanden", null)
                return
            }
            val l = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    events.success(mapOf("t" to "c", "v" to event.values[0].toLong()))
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            val handler = Handler(Looper.getMainLooper())
            val registered = try {
                // maxReportLatency 0 = nicht sammeln, sondern sofort melden.
                manager.registerListener(l, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0, handler)
            } catch (e: SecurityException) {
                false
            }
            if (registered) {
                listener = l
                registerDetector(manager, events, handler)
            } else {
                events.error("denied", "Schrittzähler konnte nicht aktiviert werden (Berechtigung?)", null)
            }
        }

        private fun registerDetector(
            manager: SensorManager,
            events: EventChannel.EventSink,
            handler: Handler,
        ) {
            val detector = manager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) ?: return
            val d = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    events.success(mapOf("t" to "s", "v" to 1L))
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            val ok = try {
                manager.registerListener(d, detector, SensorManager.SENSOR_DELAY_NORMAL, 0, handler)
            } catch (e: SecurityException) {
                false
            }
            if (ok) detectorListener = d
        }

        override fun onCancel(arguments: Any?) {
            val manager = sensorManager(context)
            listener?.let { manager?.unregisterListener(it) }
            detectorListener?.let { manager?.unregisterListener(it) }
            listener = null
            detectorListener = null
        }
    }
}
