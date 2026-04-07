/*
 * ProtoSmartCane Firmware - Main Controller
 *
 * This firmware implements a power-aware smart cane system with:
 * - Multi-sensor obstacle detection (LiDAR, Ultrasonic, IMU)
 * - Heart rate monitoring for emergency detection
 * - Battery-aware power management with automatic mode switching
 * - BLE communication for mobile app integration
 * - Haptic/audio feedback for user alerts
 *
 * Required Libraries (install via Arduino IDE Library Manager):
 * - PulseSensorPlayground: https://github.com/WorldFamousElectronics/PulseSensorPlayground
 * - Adafruit LSM6DSOX: https://github.com/adafruit/Adafruit_LSM6DSOX
 * - ArduinoBLE (if using BLE features)
 */

// Core Arduino libraries
#include <Arduino.h>
#include <Wire.h>        // For I2C communication
#include <math.h>        // For IMU calculations

// Project modules
#include "mux/mux.h"
#include "sensors/sensors.h"
#include "sensors/fushion.h/fushion.h/fushion.h.ino"  // Fusion logic
#include "responses/responses.h"
#include "mode/mode.h"
#include "faults/faults.h"
#include "ble/ble.h"

void setup() {
    // Initialize serial for debugging and monitoring
    Serial.begin(115200);
    delay(1000);  // Allow serial to initialize

    // Initialize I2C multiplexer first (required for all sensor I2C communication)
    muxInit();

    // Set initial mode to NORMAL (balanced performance/power consumption)
    setMode(NORMAL);

    // Initialize all sensor systems in order
    initSensors();      // IMU, Ultrasonic, LiDAR, Pulse sensors

    // Initialize output actuators for user feedback
    initActuators();    // Buzzer and LED

    // Initialize BLE for mobile app communication
    initBLE();

    Serial.println("=== ProtoSmartCane System Ready ===");
    Serial.println("Mode: NORMAL | Battery: Monitoring | Sensors: Active");
}

void loop() {
    // Timing variables for sensor polling intervals (mode-dependent)
    static unsigned long lastIMU = 0;
    static unsigned long lastUltrasonic = 0;
    static unsigned long lastLidar = 0;
    static unsigned long lastPulse = 0;
    static unsigned long lastBatteryCheck = 0;

    unsigned long now = millis();

    // === SENSOR POLLING (Mode-dependent intervals) ===
    // Each sensor updates at different rates based on current power mode

    // IMU: Acceleration/Gyroscope for fall detection and orientation tracking
    if (now - lastIMU > config.imuInterval) {
        updateIMU();  // Updates imu.ax, imu.ay, imu.az, imu.gx, imu.gy, imu.gz
        lastIMU = now;
    }

    // Ultrasonic: Short-range obstacle detection (typically side/back sensors)
    if (now - lastUltrasonic > config.ultrasonicInterval) {
        updateUltrasonic();  // Updates ultrasonicDistances[], ultrasonicNear, ultrasonicImminent
        lastUltrasonic = now;
    }

    // LiDAR: Forward-looking obstacle detection (primary navigation sensor)
    if (now - lastLidar > config.lidarInterval) {
        updateLidar();  // Updates lidarDistance, obstacleNear, obstacleImminent
        lastLidar = now;
    }

    // Pulse Sensor: Heart rate monitoring for emergency detection
    if (now - lastPulse > config.pulseInterval) {
        updatePulse();  // Updates heartBPM, heartRaw, pulseDetected, heartAbnormal
        lastPulse = now;
    }

    // === BATTERY MONITORING (Power Management Core) ===
    if (now - lastBatteryCheck > config.batteryCheckInterval) {
        batteryLevel = getBatteryLevel();  // Updates global batteryLevel (0-100%)

        // Automatic power mode switching based on battery level
        if (batteryLevel < 20 && currentMode != EMERGENCY) {
            setMode(LOW_POWER);
            Serial.println("MODE CHANGE: LOW_POWER (Battery < 20%)");
        } else if (batteryLevel >= 30 && currentMode == LOW_POWER) {
            setMode(NORMAL);
            Serial.println("MODE CHANGE: NORMAL (Battery >= 30%)");
        }
        lastBatteryCheck = now;
    }

    // === FAULT DETECTION ===
    checkFaults();  // Check for sensor failures (imu_fail, etc.)

    // === SITUATION FUSION ===
    fuseSituations();  // Combine all sensor data into currentSituation enum

    // === MODE CONTROL (Priority-based Emergency System) ===
    if (currentSituation == FALL_DETECTED || faults.imu_fail) {
        // EMERGENCY: Highest priority - overrides all other modes
        setMode(EMERGENCY);
        Serial.println("EMERGENCY MODE: Fall detected or IMU failure");
    } else if (currentSituation == HIGH_STRESS) {
        // Emergency: Abnormal heart rate + close obstacles
        setMode(EMERGENCY);
        Serial.println("EMERGENCY MODE: High stress condition");
    } else if (currentMode == EMERGENCY &&
               currentSituation != FALL_DETECTED &&
               currentSituation != HIGH_STRESS &&
               !faults.imu_fail) {
        // Exit emergency mode when situation clears
        setMode(batteryLevel < 20 ? LOW_POWER : NORMAL);
        Serial.println("EMERGENCY CLEARED: Returning to normal operation");
    }
    // Note: HIGH_ALERT mode removed - no physical button exists for user activation

    // === USER RESPONSE SYSTEM ===
    handleResponse();  // Generate haptic/audio feedback based on currentSituation

    // === BLE COMMUNICATION ===
    updateBLE();  // Send telemetry to mobile app (battery%, pulse BPM, yaw angle, etc.)
}
