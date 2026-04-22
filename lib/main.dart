import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/router.dart';
import 'core/theme.dart';
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

class ICanApp extends StatelessWidget {
  const ICanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = buildRouter();

    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp.router(
        title: 'iCan',
        debugShowCheckedModeBanner: false,
        theme: ICanTheme.lightTheme,
        darkTheme: ICanTheme.darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: router,
      ),
    );
  }
}
