import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/nav_screen.dart';

/// Simple named-route map for the iCan App.
class AppRouter {
  AppRouter._();

  static const String home = '/';
  static const String nav = '/nav';

  static Map<String, WidgetBuilder> get routes => {
    home: (context) => const HomeScreen(),
    nav: (context) => const NavScreen(),
  };
}
