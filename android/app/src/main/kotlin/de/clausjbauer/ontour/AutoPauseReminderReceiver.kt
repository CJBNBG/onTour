package de.clausjbauer.ontour

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Wird durch den in [AutoPauseReminderScheduler] geplanten Alarm
 * ausgelöst, wenn eine Track-Aufzeichnung bereits seit der in den
 * Einstellungen gewählten Wartezeit (siehe README Abschnitt 22,
 * AppPreferences.autoPauseReminderMinutes) ununterbrochen pausiert ist, OHNE dass der
 * Nutzer sie zwischenzeitlich fortgesetzt oder beendet hat - zeigt dafür
 * eine Benachrichtigung an, die beim Antippen die App öffnet.
 *
 * WICHTIG (Robustheit): Dieser Receiver läuft vollständig unabhängig
 * davon, ob der eigentliche App-Prozess (inkl. der in Abschnitt 21
 * beschriebenen persistenten FlutterEngine) zu diesem Zeitpunkt überhaupt
 * noch existiert - Android startet dafür bei Bedarf kurzzeitig einen
 * eigenen, minimalen Prozess. Selbst wenn also während einer Pause aus
 * irgendeinem Grund (z. B. aggressives herstellerspezifisches
 * Akku-Management, siehe Abschnitt 19) der komplette App-Prozess beendet
 * würde, bekäme der Nutzer die Erinnerung trotzdem zuverlässig
 * angezeigt.
 */
class AutoPauseReminderReceiver : BroadcastReceiver() {

    companion object {
        private const val CHANNEL_ID = "ontour_auto_pause_reminder"
        private const val NOTIFICATION_ID = 4712
    }

    override fun onReceive(context: Context, intent: Intent) {
        ensureNotificationChannel(context)

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.apply {
            // NEU (siehe README Abschnitt 23): Signalisiert MainActivity,
            // dass beim Öffnen direkt zum Track-Tab gewechselt werden
            // soll, da dort die zum Beenden/Fortsetzen nötigen
            // Bedienelemente liegen - der Nutzer würde sonst erst manuell
            // vom Start-Tab (Tacho) dorthin wechseln müssen.
            putExtra(MainActivity.EXTRA_OPEN_TRACK_TAB, true)
            // FLAG_ACTIVITY_NEW_TASK: nötig, da dieser Intent aus einem
            // Nicht-Activity-Kontext (BroadcastReceiver) heraus gestartet
            // wird. FLAG_ACTIVITY_CLEAR_TOP zusammen mit dem in der
            // AndroidManifest.xml gesetzten `launchMode="singleTask"`
            // sorgt dafür, dass eine bereits existierende MainActivity-
            // Instanz wiederverwendet (onNewIntent) statt eine zweite,
            // parallele Instanz erzeugt wird - wichtig, da beide sich
            // sonst dieselbe, persistente FlutterEngine (siehe Abschnitt
            // 21) streitig machen würden.
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            // Dieselbe Bilddatei, die auch als Launcher-Icon dient (siehe
            // README Abschnitt 14 sowie die Foreground-Service-
            // Benachrichtigung in TrackRecordingService) - für eine
            // einheitliche, sofort erkennbare App-Identität.
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle("Track-Aufzeichnung pausiert")
            .setContentText("Deine Aufzeichnung läuft seit einer Weile pausiert. Jetzt beenden?")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Pausierte Aufzeichnung",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        manager.createNotificationChannel(channel)
    }
}
