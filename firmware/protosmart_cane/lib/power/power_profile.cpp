/*
 * Power Consumption Profiles - Optimized for 4400mAh LiPo battery
 * 
 * TARGET RUNTIMES (usable capacity: 4400 × 0.9 = 3960 mAh):
 *   NORMAL: 8 hours continuous = 495 mA avg (3960 mAh / 8h)
 *   LOW_POWER: 15 hours (battery <20% fallback) = 264 mA avg (3960 / 15h)
 *   HIGH_STRESS: 4 hours peak (close obstacle + abnormal HR) = 990 mA (3960 / 4h)
 *   EMERGENCY: Fall/critical alert, ≤60s = 660 mA unrestricted (user safety priority)
 */

#include "power_profile.h"

// PROFILE_NORMAL: Aggressive responsive navigation for 8-hour continuous operation
// Strategy: High sensor sampling (20-20Hz) and BLE feedback for early obstacle detection.
//           Haptic feedback uses distance-graded patterns (weak→medium→intense as distance decreases).
//           LED active in low-light for visibility. Fast app telemetry (10 Hz).
// Power budget: 341 mA avg (scales to 8h with typical activity variation).
const PowerProfile PROFILE_NORMAL = {
    .name = "NORMAL",
    .imuPower = 8.0f,              // 20 Hz IMU - continuous fall + motion monitoring
    .ultrasonicPower = 50.0f,      // 15 Hz total (2x sensors) - frequent proximity checks
    .matrixSensorPower = 80.0f,    // 20 Hz 8x8 sensor - rapid forward updates
    .pulsePower = 8.0f,            // 10 Hz heart rate - real-time stress detection capability
    .ledPower = 40.0f,             // LED ~50% brightness in low-light (active navigation mode)
    .hapticPower = 30.0f,          // Distance-graded haptic: FAR(weak/slow) → IMMINENT(strong/fast)
    .ble_txPower = 40.0f,          // 10 Hz telemetry with full packet detail
    .esp32_basePower = 85.0f,      // Core @ 160MHz for responsive fusion
    .totalActivePower = 341.0f     // Scales to ~8h typical use
};

// PROFILE_LOW_POWER: Battery-saving fallback (active only when battery <20%)
// Strategy: Minimal sensor polling, no LED, gentle feedback, sparse BLE.
//           Maintains fall detection capability but at reduced responsiveness.
// Power budget: 98 mA avg (scales to 15h target).
const PowerProfile PROFILE_LOW_POWER = {
    .name = "LOW_POWER",
    .imuPower = 2.0f,              // 5 Hz IMU - fall detection baseline
    .ultrasonicPower = 12.0f,      // 5 Hz total (2x sensors) - coarse safety checks
    .matrixSensorPower = 20.0f,    // 5 Hz 8x8 sensor - sparse forward awareness
    .pulsePower = 1.0f,            // 2 Hz heart rate - minimal overhead
    .ledPower = 0.0f,              // LED off (battery preservation)
    .hapticPower = 5.0f,           // Minimal gentle feedback only
    .ble_txPower = 8.0f,           // 2 Hz telemetry (reduced bandwidth)
    .esp32_basePower = 50.0f,      // Core @ 80MHz (minimal processing)
    .totalActivePower = 98.0f      // Scales to ~15h
};

// PROFILE_HIGH_STRESS: Peak threat response mode
// Trigger: Close obstacle (≤200mm) AND abnormal heart rate detected simultaneously.
// Strategy: Very high sensor sampling (30-50Hz), full LED, maximum haptic alerting,
//           rapid BLE updates (20 Hz) for imminent threat awareness.
// Power budget: 700 mA avg (scales to 4h peak sustained response).
const PowerProfile PROFILE_HIGH_STRESS = {
    .name = "HIGH_STRESS",
    .imuPower = 15.0f,             // 50 Hz IMU - rapid motion + balance threats
    .ultrasonicPower = 120.0f,     // 30 Hz total (2x) - very frequent proximity
    .matrixSensorPower = 150.0f,   // 30 Hz 8x8 sensor - rapid threat updates
    .pulsePower = 15.0f,           // 20 Hz heart rate - stress level tracking
    .ledPower = 100.0f,            // LED full brightness (visible alert)
    .hapticPower = 100.0f,         // Maximum intensity + rapid pulsing alert
    .ble_txPower = 80.0f,          // 20 Hz telemetry - rapid app notifications
    .esp32_basePower = 120.0f,     // Core @ 240MHz full performance
    .totalActivePower = 700.0f     // Peak threat response sustained
};

// PROFILE_EMERGENCY: Fall detection / critical alert response
// Trigger: FREE_FALL phase detected → IMPACT confirmed → alert timeout ≤60s.
// Strategy: Maximum sampling on all sensors for impact confirmation + user tracking.
//           ZERO haptic feedback (person is already falling, haptics not useful for safety).
//           Maximum BLE telemetry (50 Hz) with detailed sensor snapshot for emergency response.
//           Time-limited: 30s standard timeout, extendable to 60s if new impacts detected.
// Power budget: Unrestricted (<60s duration), user safety is priority.
const PowerProfile PROFILE_EMERGENCY = {
    .name = "EMERGENCY",
    .imuPower = 25.0f,             // 100 Hz IMU - maximum fall impact resolution
    .ultrasonicPower = 150.0f,     // 40 Hz total (2x) - ground impact + environment mapping
    .matrixSensorPower = 180.0f,   // 40 Hz 8x8 sensor - detailed landing site mapping
    .pulsePower = 25.0f,           // 40 Hz heart rate - capture stress spike detail
    .ledPower = 150.0f,            // LED maximum + beacon/strobe pattern possible
    .hapticPower = 0.0f,           // NO haptic during fall (not useful when airborne/down)
    .ble_txPower = 120.0f,         // 50 Hz telemetry - maximum sensor snapshot detail to app
    .esp32_basePower = 160.0f,     // Core @ 240MHz maximum
    .totalActivePower = 815.0f     // Short-duration (≤60s) maximum response
};

// CAUTIOUS_SLEEP: Minimal activity, waiting for motion
const PowerProfile PROFILE_CAUTIOUS_SLEEP = {
    .name = "CAUTIOUS_SLEEP",
    .imuPower = 0.5f,              // LSM6DSOX at 1.6 Hz + interrupt wake
    .ultrasonicPower = 0.0f,       // Disabled
    .matrixSensorPower = 0.0f,     // Disabled
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
    .matrixSensorPower = 0.0f,     // Disabled
    .pulsePower = 0.0f,            // Disabled
    .ledPower = 0.0f,              // LED off
    .hapticPower = 0.0f,           // Haptic off
    .ble_txPower = 0.5f,           // BLE minimal (keep connectable)
    .esp32_basePower = 10.0f,      // ESP32 light sleep / ULP
    .totalActivePower = 10.6f      // Total - Minimum sustainable power
};