import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/route_constants.dart';
import '../services/device_prefs_service.dart';
import '../services/tts_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce(
        'Welcome to iCan. Choose your role. Double tap I am the User, or I am a Caretaker.',
        TextDirection.ltr,
      );
      TtsService.instance.speak(
        'Welcome to iCan. Are you the user, or a caretaker? Tap your role to continue.',
      );
    });
  }

  Future<void> _selectRole(String role, String routeName) async {
    HapticFeedback.mediumImpact();
    await DevicePrefsService.instance.saveUserRole(role);
    if (!mounted) return;

    // First-time users go to device pairing
    final eyeId = await DevicePrefsService.instance.getLastDeviceId();
    final caneId = await DevicePrefsService.instance.getLastCaneDeviceId();
    final neverPaired =
        (eyeId == null || eyeId.isEmpty) && (caneId == null || caneId.isEmpty);

    if (!mounted) return;

    if (neverPaired && role == 'user') {
      context.goNamed(Routes.devicePairingName);
    } else {
      context.goNamed(routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final contentWidth = isWide ? 480.0 : constraints.maxWidth;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 32 : 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/ican-app-icon.png',
                            width: 80,
                            height: 80,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text(
                          'Welcome to iCan',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'How are you using iCan today?',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(179),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      _buildRoleCard(
                        context,
                        title: 'I am the User',
                        subtitle: 'Navigate, describe scenes, and stay safe.',
                        icon: CupertinoIcons.person_crop_circle,
                        onTap: () => _selectRole('user', Routes.homeName),
                      ),
                      const SizedBox(height: 20),
                      _buildRoleCard(
                        context,
                        title: 'I am a Caretaker',
                        subtitle: 'Monitor vitals and location remotely.',
                        icon: CupertinoIcons.heart_circle,
                        onTap: () =>
                            _selectRole('caretaker', 'caretaker-dashboard'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      hint: 'Double tap to select this role',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(51),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.onSurface.withAlpha(13),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          height: 1.3,
                          color: theme.colorScheme.onSurface.withAlpha(153),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ExcludeSemantics(
                child: Icon(
                  CupertinoIcons.chevron_right,
                  color: theme.colorScheme.onSurface.withAlpha(77),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
