import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/route_constants.dart';
import '../services/ble_service.dart';

/// Connection Error Screen — Displayed when auto-connect fails on startup.
///
/// Allows user to:
/// - Retry auto-connect attempt
/// - Scan for devices manually
/// - Continue to app offline/without Eye connection
class ConnectionErrorScreen extends StatefulWidget {
  const ConnectionErrorScreen({
    super.key,
    this.errorCode,
    this.customErrorMessage,
  });

  /// Optional error code describing why connection failed
  final BleConnectionError? errorCode;
  
  /// Custom error message (overrides default from errorCode)
  final String? customErrorMessage;

  @override
  State<ConnectionErrorScreen> createState() => _ConnectionErrorScreenState();
}

class _ConnectionErrorScreenState extends State<ConnectionErrorScreen> {
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorMessage = widget.customErrorMessage ?? 
        (widget.errorCode?.message ?? 'Failed to connect to iCan Eye');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error Icon
              Icon(
                Icons.bluetooth_disabled,
                size: 80.0,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 32.0),

              // Error Title
              Text(
                'Connection Failed',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16.0),

              // Error Message
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(200),
                ),
              ),
              const SizedBox(height: 48.0),

              // Retry Button
              SizedBox(
                width: double.infinity,
                height: 56.0,
                child: ElevatedButton.icon(
                  onPressed: _isRetrying ? null : _handleRetry,
                  icon: _isRetrying
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: SizedBox(
                            width: 20.0,
                            height: 20.0,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isRetrying ? 'Retrying...' : 'Retry Connection'),
                ),
              ),
              const SizedBox(height: 12.0),

              // Manual Scan Button
              SizedBox(
                width: double.infinity,
                height: 56.0,
                child: OutlinedButton.icon(
                  onPressed: _isRetrying ? null : _handleManualScan,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan for Devices'),
                ),
              ),
              const SizedBox(height: 12.0),

              // Continue Offline Button
              SizedBox(
                width: double.infinity,
                height: 56.0,
                child: TextButton.icon(
                  onPressed: _isRetrying ? null : _handleContinueOffline,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue Offline'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);

    BleService.instance.startScan();
    BleService.instance.startScanForCane();

    await Future.delayed(const Duration(seconds: 10));

    if (!mounted) return;

    final eyeConnected =
        BleService.instance.state == BleConnectionState.connected;
    final caneConnected =
        BleService.instance.caneState == BleConnectionState.connected;

    if (eyeConnected || caneConnected) {
      context.goNamed(Routes.homeName);
    } else {
      setState(() => _isRetrying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still unable to connect. Try scanning for devices.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleManualScan() {
    context.goNamed(Routes.homeName);
  }

  void _handleContinueOffline() {
    context.goNamed(Routes.homeName);
  }
}
