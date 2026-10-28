import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';

import '../../util/track_profile_calculator.dart';
import 'profile_chart.dart';

/// Stellt die vier Profil-Diagramme - Geschwindigkeit, Höhe, Anstieg
/// (Netto-Höhenänderung seit Start, in Metern) und Steigung/Gefälle (in
/// Prozent) - für eine bereits berechnete Liste von [TrackProfilePoint]s
/// dar. Gemeinsam genutzt vom Details-Tab der laufenden Aufzeichnung
/// (TrackPage) UND vom Details-Tab eines bereits gespeicherten Tracks
/// (TrackDetailPage) - siehe README Abschnitt 29.
///
/// Nimmt bewusst die bereits BERECHNETEN [TrackProfilePoint]s entgegen
/// (statt roher `TrackPoint`s und selbst `TrackProfileCalculator.compute`
/// aufzurufen): Auf der Track-Seite werden dieselben Werte zusätzlich für
/// die Momentanwerte-Karte oberhalb der Diagramme benötigt (siehe dort) -
/// die Berechnung soll pro Rebuild nur einmal erfolgen, nicht doppelt.
class TrackProfileCharts extends StatelessWidget {
  final List<TrackProfilePoint> profile;

  const TrackProfileCharts({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: AutoHyphenatingText(
            'Noch nicht genügend Daten für Profil-Diagramme.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final distancesKm = [for (final p in profile) p.distanceMeters / 1000];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileChart(
          title: 'Geschwindigkeitsprofil',
          color: scheme.primary,
          unit: 'km/h',
          valueFormatter: (v) => v.toStringAsFixed(1),
          points: [
            for (var i = 0; i < profile.length; i++)
              if (profile[i].speedMetersPerSecond != null)
                Offset(distancesKm[i], profile[i].speedMetersPerSecond! * 3.6),
          ],
        ),
        const SizedBox(height: 28),
        ProfileChart(
          title: 'Höhenprofil',
          color: scheme.secondary,
          unit: 'm ü. NN',
          valueFormatter: (v) => v.toStringAsFixed(0),
          points: [
            for (var i = 0; i < profile.length; i++)
              if (profile[i].altitudeMeters != null)
                Offset(distancesKm[i], profile[i].altitudeMeters!),
          ],
        ),
        const SizedBox(height: 28),
        ProfileChart(
          title: 'Anstiegsprofil (Höhenänderung seit Start)',
          color: scheme.tertiary,
          unit: 'm',
          showZeroLine: true,
          valueFormatter: _formatSigned,
          points: [
            for (var i = 0; i < profile.length; i++)
              if (profile[i].netAltitudeChangeMeters != null)
                Offset(distancesKm[i], profile[i].netAltitudeChangeMeters!),
          ],
        ),
        const SizedBox(height: 28),
        ProfileChart(
          title: 'Steigung / Gefälle',
          color: scheme.error,
          unit: '%',
          showZeroLine: true,
          valueFormatter: (v) => _formatSigned(v, decimals: 1),
          points: [
            for (var i = 0; i < profile.length; i++)
              if (profile[i].gradientPercent != null)
                Offset(distancesKm[i], profile[i].gradientPercent!),
          ],
        ),
      ],
    );
  }

  /// Formatiert einen vorzeichenbehafteten Wert mit explizitem "+" bei
  /// positiven Werten (negative Werte tragen ihr "-" ohnehin bereits von
  /// Natur aus) - macht auf einen Blick klar, ob Anstieg/Steigung gerade
  /// positiv oder negativ ist, statt eine "nackte" Zahl ohne Vorzeichen
  /// interpretieren zu müssen.
  static String _formatSigned(double value, {int decimals = 0}) {
    final formatted = value.toStringAsFixed(decimals);
    return value >= 0 ? '+$formatted' : formatted;
  }
}
