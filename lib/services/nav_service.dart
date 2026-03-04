import 'package:flutter/foundation.dart';

/// A single step in a navigation route.
class NavStep {
  final String instruction; // e.g., "Turn left on Main St"
  final double distanceMeters;
  final double durationSeconds;
  final String maneuver; // e.g., "turn-left", "turn-right", "arrive"

  const NavStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuver,
  });
}

/// Navigation Service — wraps Mapbox Directions API.
///
/// Takes a destination string (from STT), geocodes it, and returns
/// turn-by-turn walking directions as a list of [NavStep]s.
class NavService extends ChangeNotifier {
  // TODO: Replace with actual Mapbox API key
  // ignore: unused_field
  static const String _mapboxToken = 'YOUR_MAPBOX_API_TOKEN';

  List<NavStep> _steps = [];
  List<NavStep> get steps => _steps;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  NavStep? get currentStep =>
      _currentStepIndex < _steps.length ? _steps[_currentStepIndex] : null;

  /// Fetch walking directions from current location to [destination].
  Future<bool> getDirections(String destination) async {
    // TODO: Implement with Mapbox Directions API
    // 1. Geocode destination string → coordinates
    // 2. Get current GPS location
    // 3. Request walking directions
    // 4. Parse response into NavStep list
    debugPrint('[Nav] Getting directions to: "$destination"');

    // Placeholder steps for development
    _steps = [
      const NavStep(
        instruction: 'Head north on Current Street',
        distanceMeters: 150,
        durationSeconds: 120,
        maneuver: 'depart',
      ),
      const NavStep(
        instruction: 'Turn left on Main Street',
        distanceMeters: 300,
        durationSeconds: 240,
        maneuver: 'turn-left',
      ),
      const NavStep(
        instruction: 'Arrive at destination on the right',
        distanceMeters: 50,
        durationSeconds: 40,
        maneuver: 'arrive',
      ),
    ];

    _currentStepIndex = 0;
    _isNavigating = true;
    notifyListeners();
    return true;
  }

  /// Advance to the next navigation step.
  void advanceStep() {
    if (_currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      notifyListeners();
    } else {
      _isNavigating = false;
      notifyListeners();
    }
  }

  /// Cancel current navigation.
  void cancelNavigation() {
    _isNavigating = false;
    _steps = [];
    _currentStepIndex = 0;
    notifyListeners();
  }

  /// Convert maneuver string to a nav command name for BLE.
  /// Returns the maneuver type for the BLE service to map to NavCommand.
  String get currentManeuver => currentStep?.maneuver ?? 'stop';
}
