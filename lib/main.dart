import 'package:flutter/material.dart';
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
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('[main] NotificationService.init() failed: $e');
  }

  await TtsService.instance.init();
  await SttService.instance.init();

  appSettingsProvider = SettingsProvider(ttsService: TtsService.instance);

  voiceCommandService = VoiceCommandService(
    tts: TtsService.instance,
    stt: SttService.instance,
    ble: BleService.instance,
  );
  voiceCommandService.attachSettings(appSettingsProvider);

  runApp(const ICanApp());
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
