import 'package:flutter/material.dart';

/// Navigation Screen — Active turn-by-turn guidance.
///
/// Shows the current navigation step and sends commands to the
/// cane via BLE. Primarily voice-driven with TTS reading each step.
class NavScreen extends StatelessWidget {
  const NavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigating'),
        centerTitle: true,
        leading: Semantics(
          button: true,
          label: 'Cancel navigation and go back',
          child: IconButton(
            icon: const Icon(Icons.close, size: 28),
            onPressed: () {
              // TODO: Cancel navigation in NavService, stop BLE commands
              Navigator.pop(context);
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Current Step Card ---
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Direction icon
                      Icon(
                        Icons.arrow_upward, // TODO: Dynamic based on maneuver
                        size: 96,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(height: 24),
                      // Instruction text
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          // TODO: Replace with NavService.currentStep.instruction
                          'Head north on Current Street',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        // TODO: Replace with actual distance
                        '150 meters',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Step progress ---
              Semantics(
                label: 'Step 1 of 3',
                child: Text(
                  // TODO: Dynamic step count from NavService
                  'Step 1 of 3',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),

              const SizedBox(height: 16),

              // --- Stop Navigation ---
              Semantics(
                button: true,
                label: 'Stop navigation',
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Cancel nav, send NAV_STOP to cane
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.stop, size: 28),
                  label: const Text('Stop Navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    minimumSize: const Size(double.infinity, 64),
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
