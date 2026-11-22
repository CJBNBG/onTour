/// Zählweise des Schrittzählers (siehe README Abschnitt 72) - in den
/// Einstellungen (Unterreiter "Start") wählbar.
///
/// Beide Zählweisen nutzen denselben Hardware-Sensor; sie unterscheiden sich
/// nur darin, welche Differenz von Zählerständen angezeigt wird.
enum StepCountMode {
  allDay(
    label: 'Ganztägig',
    description: 'Zählt die Schritte des ganzen Tages (ab Mitternacht), auch ohne '
        'Aufzeichnung. Läuft eine Track-Aufzeichnung, steht deren Schrittzahl '
        'zusätzlich in der Kachel.',
  ),
  recording(
    label: 'Nur Aufzeichnung',
    description: 'Zählt nur die Schritte während einer Track-Aufzeichnung (ohne '
        'manuelle Pausen). Ohne Aufzeichnung zeigt die Kachel keinen Wert.',
  );

  final String label;
  final String description;

  const StepCountMode({required this.label, required this.description});
}
