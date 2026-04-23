import 'dart:io';

/// Lightweight network reachability check.
/// Uses DNS lookup with a short timeout — no extra dependency needed.
class ConnectivityService {
  /// Returns true if the device can reach the internet.
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
