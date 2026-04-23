import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/app_router.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('[main] NotificationService.init() failed: $e');
  }

  runApp(const ICanApp());
}

/// iCan App — Assistive navigation and awareness for the visually impaired.
class ICanApp extends StatelessWidget {
  const ICanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iCan',
      debugShowCheckedModeBanner: false,
      theme: ICanTheme.darkTheme,
      initialRoute: AppRouter.splash,
      routes: AppRouter.routes,
    );
  }
}

