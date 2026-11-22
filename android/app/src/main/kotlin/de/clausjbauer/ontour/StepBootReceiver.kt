package de.clausjbauer.ontour

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * NEU (README Abschnitt 72): Plant den Mitternachts-Alarm des Schrittzählers
 * nach einem Neustart des Geräts bzw. nach einem App-Update neu - Alarme des
 * AlarmManagers gehen in beiden Fällen verloren.
 */
class StepBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val appContext = context.applicationContext
            // Nur, wenn der Schrittzähler jemals aktiviert wurde.
            if (StepCounterBridge.isEnabled(appContext)) StepCounterBridge.scheduleMidnight(appContext)
        }
    }
}
