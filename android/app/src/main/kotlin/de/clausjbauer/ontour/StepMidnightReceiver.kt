package de.clausjbauer.ontour

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * NEU (README Abschnitt 72): Wird kurz nach 00:00 Uhr vom AlarmManager
 * ausgelöst (siehe [StepCounterBridge.scheduleMidnight]) und merkt sich den
 * dann aktuellen Zählerstand des Schrittsensors als Tagesbeginn - Grundlage
 * für die exakte Tageszahl, auch wenn die App nicht geöffnet war.
 *
 * Läuft unabhängig vom App-Prozess (Android startet bei Bedarf kurz einen
 * eigenen). Plant zuerst den Alarm für die nächste Nacht, damit die Kette
 * auch dann nicht abreißt, wenn das Lesen des Sensors scheitert (z. B.
 * Berechtigung entzogen). `goAsync()` hält den Receiver offen, bis der Sensor
 * geantwortet hat (höchstens ca. 8 s).
 */
class StepMidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        StepCounterBridge.scheduleMidnight(appContext)

        val pending = goAsync()
        StepCounterBridge.readOnce(appContext, 8000) { value ->
            if (value != null) StepCounterBridge.saveMidnightSnapshot(appContext, value)
            pending.finish()
        }
    }
}
