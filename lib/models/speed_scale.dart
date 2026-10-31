import 'speed_unit.dart';

/// Wählbare Skalenenden (Maximalwerte) des analogen Tachos je
/// Anzeigeeinheit. Die Werte gelten in der jeweiligen Einheit selbst
/// (z. B. 100 = 100 km/h, wenn km/h gewählt ist).
class SpeedScale {
  SpeedScale._();

  static List<int> optionsFor(SpeedUnit unit) {
    switch (unit) {
      case SpeedUnit.metersPerSecond:
        return const [5, 10, 20, 50];
      case SpeedUnit.kilometersPerHour:
        return const [50, 100, 200, 300];
      case SpeedUnit.knots:
        return const [10, 20, 50, 100];
      case SpeedUnit.milesPerHour:
        return const [30, 60, 120, 180];
    }
  }

  static int defaultFor(SpeedUnit unit) {
    switch (unit) {
      case SpeedUnit.metersPerSecond:
        return 10;
      case SpeedUnit.kilometersPerHour:
        return 100;
      case SpeedUnit.knots:
        return 20;
      case SpeedUnit.milesPerHour:
        return 60;
    }
  }

  static bool isValid(SpeedUnit unit, int value) => optionsFor(unit).contains(value);
}
