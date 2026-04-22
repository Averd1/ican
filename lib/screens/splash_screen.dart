import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_router.dart';
import '../services/ble_service.dart';
import '../services/device_prefs_service.dart';


/// Splash Screen — Dynamic startup sequence for iCan App.
///
/// Performs background initialization including BLE auto-connection.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  final List<String> _loadingMessages = [
    'Initializing BLE...',
    'Connecting to iCan Cane...',
    'Connecting to iCan Eye...',
    'Ready!'
  ];
  int _currentMessageIndex = 0;
  Timer? _messageTimer;
  bool _isInitStarted = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
    _startMessageSimulation();
    
    // Start actual initialization
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_isInitStarted) return;
    _isInitStarted = true;

    debugPrint('[Splash] Initializing app...');

    // Minimum splash display time
    await Future.delayed(const Duration(seconds: 2));

    // Fire-and-forget: connect both devices in background, don't block navigation.
    // Auto-reconnect on disconnect is handled inside BleService.
    final savedEyeMac = await DevicePrefsService.instance.getLastDeviceId()
        ?? BleService.fallbackEyeDeviceId;
    BleService.instance.connectToEyeByMac(savedEyeMac);
    BleService.instance.autoConnectToCane();

    debugPrint('[Splash] Initialization complete.');
    _navigateToHome();
  }

  void _startMessageSimulation() {
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_currentMessageIndex < _loadingMessages.length - 1) {
        if (mounted) {
          setState(() {
            _currentMessageIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(AppRouter.roleSelection);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Semantics(
        label: 'App loading: ${_loadingMessages[_currentMessageIndex]}',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Title Animation
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Opacity(
                      opacity: _opacityAnimation.value,
                      child: Text(
                        'iCan',
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 48),
              
              // Loading Indicator
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: theme.colorScheme.secondary,
                  strokeWidth: 4.0,
                ),
              ),
              const SizedBox(height: 24),

              // Status Message (Simulated processes)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _loadingMessages[_currentMessageIndex],
                  key: ValueKey<int>(_currentMessageIndex),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(200),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
