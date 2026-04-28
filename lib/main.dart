import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'models/settings_provider.dart';
import 'services/ble_service.dart';
import 'services/notification_service.dart';
import 'services/stt_service.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';

late final VoiceCommandService voiceCommandService;
late final SettingsProvider appSettingsProvider;

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
        FlutterError.presentError(details);
      };

      try {
        await NotificationService.init();
      } catch (e) {
        debugPrint('[main] NotificationService.init() failed: $e');
      }

      try {
        await TtsService.instance.init();
      } on PlatformException catch (e) {
        debugPrint(
          '[main] TtsService.init() platform failure: ${e.code} ${e.message}',
        );
      } catch (e) {
        debugPrint('[main] TtsService.init() failed: $e');
      }

      try {
        await SttService.instance.init();
      } catch (e) {
        debugPrint('[main] SttService.init() failed: $e');
      }

      appSettingsProvider = SettingsProvider(ttsService: TtsService.instance);

      voiceCommandService = VoiceCommandService(
        tts: TtsService.instance,
        stt: SttService.instance,
        ble: BleService.instance,
      );
      voiceCommandService.attachSettings(appSettingsProvider);

      runApp(const ICanApp());
    },
    (error, stackTrace) {
      debugPrint('[ZoneError] $error');
      debugPrintStack(stackTrace: stackTrace);
    },
  );
}

class ICanApp extends StatelessWidget {
  const ICanApp({super.key});

  static final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp.router(
        title: 'iCan',
        debugShowCheckedModeBanner: false,
        theme: ICanTheme.lightTheme,
        darkTheme: ICanTheme.darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}
