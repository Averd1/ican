import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting iCan Eye device information across app sessions.
///
/// Stores the MAC address or device ID of the last successfully connected
/// iCan Eye device, allowing automatic reconnection on app startup.
class DevicePrefsService {
  DevicePrefsService._internal();
  static final DevicePrefsService instance = DevicePrefsService._internal();

  static const String _lastEyeDeviceIdKey = 'last_eye_device_id';
  static const String _lastCaneDeviceIdKey = 'last_cane_device_id';
  static const String _userRoleKey = 'user_role';

  Future<String?> getUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userRoleKey);
    } catch (e) {
      debugPrint('[DevicePrefs] Error loading user role: $e');
      return null;
    }
  }

  Future<void> saveUserRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userRoleKey, role);
    } catch (e) {
      debugPrint('[DevicePrefs] Error saving user role: $e');
    }
  }

  /// Get the last connected iCan Eye device ID (MAC address or identifier).
  /// Returns null if no device has been saved yet.
  Future<String?> getLastDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastEyeDeviceIdKey);
    } catch (e) {
      debugPrint('[DevicePrefs] Error loading last device ID: $e');
      return null;
    }
  }

  /// Save the iCan Eye device ID (MAC address or identifier) for future auto-connect.
  Future<bool> saveLastDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_lastEyeDeviceIdKey, deviceId);
      if (success) {
        debugPrint('[DevicePrefs] Saved last device ID: $deviceId');
      }
      return success;
    } catch (e) {
      debugPrint('[DevicePrefs] Error saving device ID: $e');
      return false;
    }
  }

  /// Get the last connected iCan Cane device ID. Returns null if never saved.
  Future<String?> getLastCaneDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastCaneDeviceIdKey);
    } catch (e) {
      debugPrint('[DevicePrefs] Error loading last cane device ID: $e');
      return null;
    }
  }

  /// Save the iCan Cane device ID for future auto-connect.
  Future<bool> saveLastCaneDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_lastCaneDeviceIdKey, deviceId);
      if (success) {
        debugPrint('[DevicePrefs] Saved last cane device ID: $deviceId');
      }
      return success;
    } catch (e) {
      debugPrint('[DevicePrefs] Error saving cane device ID: $e');
      return false;
    }
  }

  /// Clear the saved device ID (called when user manually disconnects or "forgets" device).
  Future<bool> clearLastDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove(_lastEyeDeviceIdKey);
      if (success) {
        debugPrint('[DevicePrefs] Cleared last device ID');
      }
      return success;
    } catch (e) {
      debugPrint('[DevicePrefs] Error clearing device ID: $e');
      return false;
    }
  }
}
