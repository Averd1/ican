import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ICanApp());
}

/// iCan App — Assistive navigation and awareness for the visually impaired.
///
/// Voice-driven interface backed by BLE communication with the
/// iCan Cane (haptic navigation) and iCan Eye (scene description).
class ICanApp extends StatelessWidget {
  const ICanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iCan',
      debugShowCheckedModeBanner: false,
      theme: ICanTheme.darkTheme,
      initialRoute: AppRouter.home,
      routes: AppRouter.routes,
    );
  }
}
