/*
 * Power Consumption Profiles - Actual Values
 */

#include "power_profile.h"

// NORMAL MODE: 8-hour continuous operation
// Target: ~85mA average (660mAh / 8h = 82.5mA)
// Strategy: Base sensors + haptic feedback (LED/buzzer minimal)
const PowerProfile PROFILE_NORMAL = {
    .name = "NORMAL",
    .imuPower = 4.5f,              // LSM6DSOX at 52 Hz
    .ultrasonicPower = 50.0f,      // Per sensor, 10 Hz (optimize: could be lower)
    .lidarPower = 50.0f,           // TF Luna at 15-20Hz (reduced from 25Hz)
    .pulsePower = 5.0f,            // PulseSensorPlayground sampling
    .ledPower = 0.5f,              // LED minimal - only when dark + active (overhead)
    .hapticPower = 8.0f,           // Haptic active for events (efficient vs buzzer)
    .ble_txPower = 10.0f,          // BLE telemetry simplified 5 Hz (battery % + mode)
    .esp32_basePower = 35.0f,      // Core 80MHz + BLE radio
    .totalActivePower = 85.0f      // Target: 8-hour runtime at 660mAh
};

// LOW_POWER MODE: Extended mission, reduced responsiveness
const PowerProfile PROFILE_LOW_POWER = {
    .name = "LOW_POWER",
    .imuPower = 2.5f,              // LSM6DSOX at 26 Hz
    .ultrasonicPower = 25.0f,      // Per sensor, 2 Hz
    .lidarPower = 40.0f,           // TF Luna at 10 Hz (gated)
    .pulsePower = 1.0f,            // PulseSensorPlayground duty-cycled
    .ledPower = 0.0f,              // LED off
    .hapticPower = 0.0f,           // Haptic off
    .ble_txPower = 10.0f,          // BLE telemetry 1 Hz
    .esp32_basePower = 30.0f,      // Reduced core frequency if possible
    .totalActivePower = 85.0f      // Total estimated for LOW_POWER mode
};

// EMERGENCY MODE: Maximum monitoring (temporary, capped 30s)
// Strategy: High sensor polling, haptic alerts only (no LED/buzzer for power)
const PowerProfile PROFILE_EMERGENCY = {
    .name = "EMERGENCY",
    .imuPower = 8.0f,              // LSM6DSOX at 104 Hz
    .ultrasonicPower = 75.0f,      // Per sensor, 20 Hz
    .lidarPower = 100.0f,          // TF Luna at 25 Hz
    .pulsePower = 10.0f,           // PulseSensorPlayground 1000 Hz burst
    .ledPower = 0.0f,              // LED OFF (no power waste in emergency)
    .hapticPower = 50.0f,          // Haptic alerts active for feedback
    .ble_txPower = 40.0f,          // BLE telemetry 20 Hz
    .esp32_basePower = 80.0f,      // Full 240 MHz operation
    .totalActivePower = 250.0f     // Total - 40% reduction from v1 (no LED)
};

// CAUTIOUS_SLEEP: Minimal activity, waiting for motion
const PowerProfile PROFILE_CAUTIOUS_SLEEP = {
    .name = "CAUTIOUS_SLEEP",
    .imuPower = 0.5f,              // LSM6DSOX at 1.6 Hz + interrupt wake
    .ultrasonicPower = 0.0f,       // Disabled
    .lidarPower = 0.0f,            // Disabled
    .pulsePower = 0.0f,            // Duty-cycled off
    .ledPower = 0.0f,              // LED off
    .hapticPower = 0.0f,           // Haptic off
    .ble_txPower = 5.0f,           // BLE advertisement only, no notify
    .esp32_basePower = 25.0f,      // ESP32 at reduced frequency
    .totalActivePower = 30.5f      // Total - Very low power
};

// DEEP_SLEEP: Hibernation - wake only on IMU interrupt
const PowerProfile PROFILE_DEEP_SLEEP = {
    .name = "DEEP_SLEEP",
    .imuPower = 0.1f,              // IMU interrupt monitoring only
    .ultrasonicPower = 0.0f,       // Disabled
    .lidarPower = 0.0f,            // Disabled
    .pulsePower = 0.0f,            // Disabled
    .ledPower = 0.0f,              // LED off
    .hapticPower = 0.0f,           // Haptic off
    .ble_txPower = 0.5f,           // BLE minimal (keep connectable)
    .esp32_basePower = 10.0f,      // ESP32 light sleep / ULP
    .totalActivePower = 10.6f      // Total - Minimum sustainable power
};