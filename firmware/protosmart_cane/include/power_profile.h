/*
 * Power Consumption Profiles and Battery Management Configuration
 */

#pragma once

#include <Arduino.h>

// === POWER CONSUMPTION PROFILES (mA) ===
// These values are used to estimate battery lifetime

struct PowerProfile {
    const char* name;
    float imuPower;              // mA - accelerometer + gyro
    float ultrasonicPower;       // mA - per sensor
    float lidarPower;            // mA
    float pulsePower;            // mA
    float ledPower;              // mA - at full brightness
    float hapticPower;           // mA - DRV2605L active
    float ble_txPower;           // mA - BLE characteristic write + notify
    float esp32_basePower;       // mA - ESP32 core at 240 MHz
    float totalActivePower;      // mA - sum of all active components
};

// NORMAL MODE: Balanced performance for continuous navigation
extern const PowerProfile PROFILE_NORMAL;

// LOW_POWER MODE: Extended battery life
extern const PowerProfile PROFILE_LOW_POWER;

// EMERGENCY MODE: Maximum monitoring (temporary, ~30s)
extern const PowerProfile PROFILE_EMERGENCY;

// CAUTIOUS_SLEEP: Minimal sampling, waiting for motion
extern const PowerProfile PROFILE_CAUTIOUS_SLEEP;

// DEEP_SLEEP: Hibernation mode, wake on IMU interrupt only
extern const PowerProfile PROFILE_DEEP_SLEEP;

// === BATTERY SPECIFICATIONS ===
#define BATTERY_CAPACITY_MAH 660        // LiPo battery capacity
#define BATTERY_NOMINAL_VOLTAGE 3.7f    // Nominal voltage for runtime calc
#define BATTERY_USABLE_CAPACITY 0.9f    // 90% of rated capacity (preserve cell life)

// === SLEEP MODE THRESHOLDS ===
#define INACTIVITY_TIMEOUT_CAUTIOUS 300000  // 5 minutes to cautious sleep
#define INACTIVITY_TIMEOUT_DEEP 1200000     // 20 minutes to deep sleep
#define MOTION_THRESHOLD_WAKE 2.0f          // m/s² to wake from sleep

// === STATE HISTORY (short-term, stored in RAM) ===
#define STATE_HISTORY_SIZE 12  // Keep 12 samples (~1 minute)

struct StateHistory {
    uint8_t flags;                        // Emergency/stress flags
    uint8_t heartBPM;
    uint16_t minDistance;
    unsigned long timestamp;
};

// === BATTERY MONITORING ===
#define LOW_POWER_WARNING_THRESHOLD 15   // % - warn user battery is critical
#define CRITICAL_BATTERY_THRESHOLD 5     // % - shutdown recommendation