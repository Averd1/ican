/*
 * ProtoSmartCane Firmware - Main Controller
 *
 * DEPLOYMENT-READY VERSION with advanced power management and sensor features:
 * - Continuous fall buzzer fix (now pulsed with 30-second timeout)
 * - Ambient light sensor with auto LED illumination
 * - Distance-scaled haptic feedback (intensity + frequency)
 * - Power consumption profiles and battery lifetime estimation
 * - Sleep modes: Cautious (5min inactivity) and Deep (20min inactivity)
 * - Built-in IMU fall detection acceleration/impact detection
 * - Proper sensor error handling and state history tracking
 * - BLE protocol with runtime estimation
 * - I2C mux synchronization
 *
 * Required Libraries (install via Arduino IDE Library Manager):
 * - PulseSensorPlayground: https://github.com/WorldFamousElectronics/PulseSensorPlayground
 * - Adafruit LSM6DSOX: https://github.com/adafruit/Adafruit_LSM6DSOX
 * - ArduinoBLE (if using BLE features)
 */

#include <Arduino.h>
#include <Wire.h>
#include <math.h>

// Project includes
#include "config.h"
#include "state.h"

// Module includes
#include "mux.h"
#include "mode.h"
#include "sensors.h"
#include "sensors/light.h"
#include "fusion.h"
#include "responses.h"
#include "faults.h"
#include "ble.h"
#include "power/battery_monitor.h"
#include "power/sleep_manager.h"

// Global state variables (defined in state.h)
SystemMode currentMode = NORMAL;
ModeConfig modeConfig;
Situation currentSituation = NONE;
EmergencyType currentEmergencyType = EMERGENCY_NONE;
SensorData currentSensors = {0};
FaultState systemFaults = {false, false, false, false, 0};

bool emergencyActive = false;
unsigned long emergencyStartTime = 0;

bool obstacleNear = false;
bool obstacleImminent = false;
bool ultrasonicNear = false;
bool ultrasonicImminent = false;

unsigned long lastIMUUpdate = 0;
unsigned long lastUltrasonicUpdate = 0;
unsigned long lastLidarUpdate = 0;
unsigned long lastPulseUpdate = 0;
unsigned long lastBatteryCheck = 0;
unsigned long lastTelemetryUpdate = 0;
unsigned long lastSleepCheck = 0;

uint16_t telemetrySequence = 0;

// Battery and Power Management state
BatteryStatus batteryStatus = {0};
SleepManagerState sleepState = {NORMAL_OPERATION, 0, 0, 0, false};

// Light sensor state
LightStatus lightStatus = {0, false};

// Emergency state history (tracks last 12 emergency events ~1 min window)
unsigned long emergencyHistory[SLEEP_HISTORY_SIZE] = {0};
uint8_t emergencyHistoryIndex = 0;

void setup() {
    // Initialize serial for debugging
    Serial.begin(SERIAL_BAUD_RATE);
    delay(1000);

    if (DEBUG_MODE) {
        Serial.println("=== ProtoSmartCane Firmware v1.0 ===");
        Serial.println("Initializing system...");
    }

    // Initialize I2C multiplexer (critical for sensor communication)
    muxInit();

    // Set initial mode and configuration
    setMode(NORMAL);

    // Initialize all sensor systems
    sensorsInit();

    // Initialize light sensor (ambient lux measurement)
    lightInit();

    // Initialize battery monitor and sleep manager
    batteryMonitorInit();
    sleepManagerInit();

    // Initialize actuators (buzzer, LED, haptic)
    responsesInit();

    // Initialize BLE communication
    bleInit();

    if (DEBUG_MODE) {
        Serial.println("System initialization complete!");
        Serial.println("Mode: NORMAL | Battery: Monitoring | Sensors: Active");
    }
}

void loop() {
    unsigned long now = millis();

    // === BATTERY MONITORING (Power Management Core) ===
    if (now - lastBatteryCheck > modeConfig.batteryCheckInterval) {
        batteryStatus = getBatteryStatus();
        currentSensors.batteryLevel = batteryStatus.percentage;
        
        if (DEBUG_MODE) {
            Serial.print("Battery: ");
            Serial.print(batteryStatus.voltage_v);
            Serial.print("V (");
            Serial.print(batteryStatus.percentage);
            Serial.print("%) - ");
            Serial.print(batteryStatus.estimated_runtime_minutes);
            Serial.println(" min remaining");
        }

        // Automatic power mode switching with hysteresis
        if (batteryStatus.percentage < BATTERY_LOW_THRESHOLD && currentMode != EMERGENCY) {
            setMode(LOW_POWER);
            if (DEBUG_MODE) Serial.println("MODE CHANGE: LOW_POWER (Battery low)");
        } else if (batteryStatus.percentage >= BATTERY_RECOVERY_THRESHOLD && currentMode == LOW_POWER) {
            setMode(NORMAL);
            if (DEBUG_MODE) Serial.println("MODE CHANGE: NORMAL (Battery recovered)");
        }
        lastBatteryCheck = now;
    }

    // === SENSOR POLLING (Mode-dependent intervals) ===
    // IMU: Acceleration/Gyroscope for fall detection and orientation
    if (now - lastIMUUpdate > modeConfig.imuInterval) {
        updateIMU();
        lastIMUUpdate = now;
    }

    // Ultrasonic: Short-range obstacle detection
    if (now - lastUltrasonicUpdate > modeConfig.ultrasonicInterval) {
        updateUltrasonic();
        lastUltrasonicUpdate = now;
    }

    // LiDAR: Forward-looking obstacle detection
    if (now - lastLidarUpdate > modeConfig.lidarInterval) {
        updateLidar();
        lastLidarUpdate = now;
    }

    // Pulse Sensor: Heart rate monitoring
    if (now - lastPulseUpdate > modeConfig.pulseInterval) {
        updatePulse();
        lastPulseUpdate = now;
    }

    // Light Sensor: Ambient illumination level detection
    if (now - lastPulseUpdate > LIGHT_SENSOR_INTERVAL_MS) {
        lightStatus = getLightStatus();
        if (DEBUG_MODE && lightStatus.is_low_light) {
            Serial.print("Low-light condition detected: ");
            Serial.print(lightStatus.lux);
            Serial.println(" lux");
        }
    }

    // === SLEEP MANAGEMENT ===
    if (now - lastSleepCheck > SLEEP_CHECK_INTERVAL_MS) {
        updateSleepManager(currentSituation, currentMode);
        lastSleepCheck = now;
    }

    // === FAULT DETECTION ===
    checkFaults();

    // === SITUATION FUSION ===
    fuseSituations();

    // === EMERGENCY MODE CONTROL (Highest Priority) ===
    if (currentSituation == FALL_DETECTED || systemFaults.imu_fail) {
        if (currentMode != EMERGENCY) {
            setMode(EMERGENCY);
            currentEmergencyType = (currentSituation == FALL_DETECTED) ?
                                 EMERGENCY_FALL : EMERGENCY_SENSOR_FAIL;
            if (DEBUG_MODE) Serial.println("EMERGENCY MODE: Fall/IMU failure detected");
        }
    } else if (currentSituation == HIGH_STRESS) {
        if (currentMode != EMERGENCY) {
            setMode(EMERGENCY);
            currentEmergencyType = EMERGENCY_HIGH_STRESS;
            if (DEBUG_MODE) Serial.println("EMERGENCY MODE: High stress condition");
        }
    } else if (currentMode == EMERGENCY &&
               currentSituation != FALL_DETECTED &&
               currentSituation != HIGH_STRESS &&
               !systemFaults.imu_fail) {
        // Exit emergency mode when situation clears
        setMode(currentSensors.batteryLevel < BATTERY_LOW_THRESHOLD ? LOW_POWER : NORMAL);
        currentEmergencyType = EMERGENCY_NONE;
        emergencyActive = false;
        if (DEBUG_MODE) Serial.println("EMERGENCY CLEARED: Returning to normal operation");
    }

    // === USER RESPONSE SYSTEM ===
    handleResponses();

    // === BLE TELEMETRY ===
    // Adjust telemetry rate based on mode and emergency status
    unsigned long telemetryInterval = (currentMode == EMERGENCY) ? 50 :  // 20 Hz in emergency
                                     (currentMode == LOW_POWER) ? 1000 : // 1 Hz in low power
                                     200; // 5 Hz normal
    if (now - lastTelemetryUpdate > telemetryInterval) {
        updateBLETelemetry();
        lastTelemetryUpdate = now;
    }
}