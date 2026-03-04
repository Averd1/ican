import 'package:flutter/material.dart';
import '../core/app_router.dart';

/// Home Screen — Main entry point for the iCan App.
///
/// Designed for accessibility: large tap targets, high contrast,
/// voice-driven interaction. Shows connection status and primary actions.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('iCan'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Connection Status ---
              Semantics(
                label: 'Device connection status',
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth,
                        color: theme.colorScheme.secondary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      // TODO: Replace with actual BleService state
                      Text(
                        'Cane: Disconnected',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // --- Primary Action: Say a Location ---
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Say a location to start navigation',
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Start STT listening, get destination,
                      // then navigate to NavScreen with result
                      Navigator.pushNamed(context, AppRouter.nav);
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          size: 64,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Say a Location',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap and speak your destination',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimary.withAlpha(179),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Secondary: Connect Devices ---
              Semantics(
                button: true,
                label: 'Connect to iCan devices via Bluetooth',
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Open device scanning / connection UI
                  },
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Connect Devices'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    textStyle: const TextStyle(fontSize: 18),
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
