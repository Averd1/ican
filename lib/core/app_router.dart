import 'package:flutter/material.dart';
import '../screens/gps_screen.dart';
import '../screens/home_screen.dart';
import '../screens/nav_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/caretaker_dashboard_screen.dart';

/// Simple named-route map for the iCan App.
class AppRouter {
  AppRouter._();

  static const String splash = '/splash';
  static const String roleSelection = '/role-selection';
  static const String home = '/home';
  static const String nav = '/nav';
  static const String caretakerDashboard = '/caretaker-dashboard';
  static const String gps = '/gps';

  static Map<String, WidgetBuilder> get routes => {
    splash: (context) => const SplashScreen(),
    roleSelection: (context) => const RoleSelectionScreen(),
    home: (context) => const HomeScreen(),
    nav: (context) => const NavScreen(),
    caretakerDashboard: (context) => const CaretakerDashboardScreen(),
    gps: (context) => const GpsScreen(),
  };
}