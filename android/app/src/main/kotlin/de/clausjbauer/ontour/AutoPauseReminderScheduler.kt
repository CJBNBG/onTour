package de.clausjbauer.ontour

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * Plant bzw. storniert den nativen Erinnerungs-Alarm für eine anhaltend
 * pausierte Track-Aufzeichnung (siehe README Abschnitt 22, aufgerufen aus
 * OnTourApplication.setupAutoPauseReminderChannel).
 *
 * Bewusst `AlarmManager.setAndAllowWhileIdle` statt einer "exakten"
 * Alarm-Variante (`setExactAndAllowWhileIdle`): Für eine reine Erinnerung
 * ist eine durch den Doze-Modus verursachte Verschiebung um einige Minuten
 * unproblematisch - dafür ist im Unterschied zu exakten Alarmen unter
 * Android 12+ KEINE gesonderte, vom Nutzer manuell zu erteilende
 * "Alarme & Erinnerungen"-Berechtigung (`SCHEDULE_EXACT_ALARM`) nötig, die
 * den Einbau unnötig verkomplizieren würde.
 */
object AutoPauseReminderScheduler {
    /**
     * Fester Request-Code für den einen, immer wiederverwendeten
     * PendingIntent - ein erneuter `schedule()`-Aufruf ersetzt dadurch
     * automatisch einen zuvor für eine ANDERE Pause gesetzten Alarm,
     * statt mehrere parallel anzuhäufen.
     */
    private const val REQUEST_CODE = 4711

    fun schedule(context: Context, delayMinutes: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val triggerAtMillis = System.currentTimeMillis() + delayMinutes * 60_000L
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            reminderPendingIntent(context),
        )
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        alarmManager.cancel(reminderPendingIntent(context))
    }

    private fun reminderPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, AutoPauseReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            // FLAG_IMMUTABLE ist ab Android 12 (API 31) für PendingIntents
            // verpflichtend anzugeben - wir mutieren den Intent von
            // Empfängerseite ohnehin nie.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
