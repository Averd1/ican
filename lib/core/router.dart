import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/home_view_model.dart';
import '../models/settings_provider.dart';
import '../screens/accessible_home_screen.dart';
import '../screens/caretaker_dashboard_screen.dart';
import '../screens/connection_error_screen.dart';
import '../screens/device_pairing_screen.dart';
import '../screens/gps_screen.dart';
import '../screens/help_screen.dart';
import '../screens/live_detection_screen.dart';
import '../screens/nav_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/vision_diagnostic_screen.dart';
import '../services/device_prefs_service.dart';
import '../services/on_device_vision_service.dart';
import '../services/scene_description_service.dart';
import '../services/tts_service.dart';
import '../services/vertex_ai_service.dart';
import 'app_shell.dart';
import 'route_constants.dart';
import 'theme.dart';

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: Routes.navigatorKey,
    initialLocation: Routes.home,
    debugLogDiagnostics: false,

    redirect: _guardNoPairedDevices,

    errorBuilder: (context, state) {
      _announceScreen(Routes.notFoundName);
      return const _NotFoundScreen();
    },

    routes: [
      // Shell route wraps the three-tab bottom navigation scaffold.
      // Each branch gets its own navigator so back-stack is per-tab.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // ── Tab 0: Home ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                name: Routes.homeName,
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  name: Routes.homeName,
                  child: ChangeNotifierProvider(
                    create: (_) {
                      final aiService = VertexAiService()..loadSavedModel();
                      final onDeviceService = OnDeviceVisionService();
                      final sceneService = SceneDescriptionService(
                        cloudService: aiService,
                        onDeviceService: onDeviceService,
                      )..loadSavedMode();
                      final ttsService = TtsService()..init();
                      return HomeViewModel(
                        sceneService: sceneService,
                        ttsService: ttsService,
                      );
                    },
                    child: const AccessibleHomeScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ── Tab 1: Settings ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                name: Routes.settingsName,
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  name: Routes.settingsName,
                  child: ChangeNotifierProvider(
                    create: (_) =>
                        SettingsProvider(ttsService: TtsService()..init()),
                    child: const SettingsScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ── Tab 2: Help ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.help,
                name: Routes.helpName,
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  name: Routes.helpName,
                  child: const HelpScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Device pairing (full-screen, outside the tab shell) ──
      GoRoute(
        path: Routes.devicePairing,
        name: Routes.devicePairingName,
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: Routes.devicePairingName,
          child: DevicePairingScreen(
            onPairingComplete: () => context.goNamed(Routes.homeName),
            onSkip: () => context.goNamed(Routes.homeName),
          ),
        ),
      ),

      // ── Nav screen (pushed from home, not a tab) ──
      GoRoute(
        path: '/nav',
        name: 'nav',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'nav',
          child: const NavScreen(),
        ),
      ),

      // ── GPS screen (pushed from old home screen) ──
      GoRoute(
        path: '/gps',
        name: 'gps',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'gps',
          child: const GpsScreen(),
        ),
      ),

      // ── Live object detection (full-screen, outside tabs) ──
      GoRoute(
        path: '/live-detection',
        name: 'live-detection',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'live-detection',
          child: ChangeNotifierProvider(
            create: (_) =>
                SettingsProvider(ttsService: TtsService()..init()),
            child: const LiveDetectionScreen(),
          ),
        ),
      ),

      // ── Vision diagnostic (hidden dev tool, long-press in Settings > About) ──
      GoRoute(
        path: '/dev/vision-diagnostic',
        name: 'vision-diagnostic',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'vision-diagnostic',
          child: const VisionDiagnosticScreen(),
        ),
      ),

      // ── Splash (startup sequence) ──
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'splash',
          child: const SplashScreen(),
        ),
      ),

      // ── Role selection ──
      GoRoute(
        path: '/role-selection',
        name: 'role-selection',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'role-selection',
          child: const RoleSelectionScreen(),
        ),
      ),

      // ── Caretaker dashboard ──
      GoRoute(
        path: '/caretaker-dashboard',
        name: 'caretaker-dashboard',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'caretaker-dashboard',
          child: const CaretakerDashboardScreen(),
        ),
      ),

      // ── Connection error ──
      GoRoute(
        path: '/connection-error',
        name: 'connection-error',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          name: 'connection-error',
          child: const ConnectionErrorScreen(),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Redirect: if no devices have ever been paired, send to pairing screen.
// ─────────────────────────────────────────────────────────────────────────────

Future<String?> _guardNoPairedDevices(
    BuildContext context, GoRouterState state) async {
  if (state.matchedLocation == Routes.devicePairing) return null;
  if (state.matchedLocation.startsWith('/dev/')) return null;

  final eyeId = await DevicePrefsService.instance.getLastDeviceId();
  final caneId = await DevicePrefsService.instance.getLastCaneDeviceId();

  final neverPaired =
      (eyeId == null || eyeId.isEmpty) && (caneId == null || caneId.isEmpty);

  if (neverPaired) return Routes.devicePairing;
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page builder: fade transition (or instant when reduceMotion is on).
// Every route change announces the screen name to the accessibility framework.
// ─────────────────────────────────────────────────────────────────────────────

CustomTransitionPage<void> _buildPage({
  required GoRouterState state,
  required String name,
  required Widget child,
}) {
  _announceScreen(name);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (AppAccessibility.reduceMotion(context)) return child;
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}

void _announceScreen(String routeName) {
  final title = Routes.titleFor(routeName);
  SemanticsService.announce('$title screen', TextDirection.ltr);
}

// ─────────────────────────────────────────────────────────────────────────────
// 404 / Not Found — full screen, large text, single "Go Home" action.
// ─────────────────────────────────────────────────────────────────────────────

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  label: 'Page not found',
                  child: Text(
                    'Page Not Found',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnLight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label:
                      'The page you are looking for does not exist or has been moved.',
                  child: Text(
                    'The page you are looking for does not exist or has been moved.',
                    style: TextStyle(
                      fontSize: 20,
                      color: AppColors.textSecondaryOnLight,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  button: true,
                  label: 'Go to home screen',
                  hint: 'Returns to the main home screen',
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        context.goNamed(Routes.homeName);
                      },
                      child: const Text('Go Home'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
