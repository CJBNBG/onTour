package de.clausjbauer.ontour

/**
 * Hält - rein im Prozessspeicher, KEINE Persistierung nötig oder gewollt -
 * vor, ob bei nächster Gelegenheit von Dart-Seite aus direkt zum Track-Tab
 * gewechselt werden soll (siehe README Abschnitt 23).
 *
 * Wird von [MainActivity] gesetzt (siehe dort `handleIntent`) und von
 * HomeShell über den in [OnTourApplication] registrierten MethodChannel
 * "ontour/navigation" (Methode "consumePendingOpenTrackTab") abgefragt UND
 * dabei zurückgesetzt.
 *
 * WARUM EIN "PULL"- STATT EINES "PUSH"-MODELLS: Naheliegender wäre
 * gewesen, direkt aus [MainActivity] heraus einen MethodChannel-Aufruf
 * Richtung Dart abzusetzen ("push"), sobald das Intent-Extra erkannt
 * wird. Das würde jedoch bei einem echten Kaltstart (App-Prozess war
 * komplett beendet, wird durch Antippen der Benachrichtigung frisch
 * gestartet) eine klassische Race Condition riskieren: Ob die Dart-Seite
 * (HomeShell) zu diesem sehr frühen Zeitpunkt ihren MethodChannel-Handler
 * bereits registriert hat, ist nicht garantiert - ein zu früher "Push"
 * würde dann folgenlos verpuffen. Das hier verwendete "Pull"-Modell
 * (Dart fragt aktiv nach, sobald es so weit ist - siehe HomeShell,
 * sowohl beim Start als auch bei jedem Zurückkehren in den Vordergrund)
 * vermeidet dieses Timing-Problem vollständig.
 */
object PendingNavigation {
    var openTrackTab: Boolean = false
}
