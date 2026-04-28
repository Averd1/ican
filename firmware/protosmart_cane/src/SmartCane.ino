/*
 * ProtoSmartCane Firmware - Main Controller
 *
 * DEPLOYMENT-READY VERSION with advanced power management and sensor features:
 * - Continuous fall haptic disk pulse logic with 30-second timeout
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
#include "light.h"
#include "fusion.h"
#include "responses.h"
#include "haptic_driver.h"
#include "faults.h"
#include "ble.h"
#include "battery_monitor.h"
#include "sleep_manager.h"

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
bool imuFallDetected = false;
bool imuOrientationOk = true;

unsigned long lastIMUUpdate = 0;
unsigned long lastUltrasonicUpdate = 0;
unsigned long lastMatrixSensorUpdate = 0;
unsigned long lastPulseUpdate = 0;
unsigned long lastBatteryCheck = 0;
unsigned long lastTelemetryUpdate = 0;
unsigned long lastSleepCheck = 0;

uint16_t telemetrySequence = 0;

// Light sensor state
LightStatus lightStatus = {0, false};

// Emergency state history (tracks last 12 emergency events ~1 min window)
unsigned long emergencyHistory[STATE_HISTORY_SIZE] = {0};
uint8_t emergencyHistoryIndex = 0;

static unsigned long lastLightUpdate = 0;
static unsigned long lastSensorDebugPrint = 0;

static void printIsolatedSensorDebug(unsigned long now) {
    if (!DEBUG_MODE || now - lastSensorDebugPrint < SENSOR_DEBUG_PRINT_INTERVAL_MS) {
        return;
    }

    lastSensorDebugPrint = now;

    Serial.print("TEST | 8x8 head=");
    Serial.print(currentSensors.matrixSensorHeadDetected ? currentSensors.matrixSensorHeadDistance : SENSOR_ERROR_DISTANCE);
    Serial.print(" mm waist=");
    Serial.print(currentSensors.matrixSensorWaistDetected ? currentSensors.matrixSensorWaistDistance : SENSOR_ERROR_DISTANCE);
    Serial.print(" mm | ultraL=");
    Serial.print(currentSensors.ultrasonicDistances[0]);
    Serial.print(" mm ultraR=");
    Serial.print(currentSensors.ultrasonicDistances[1]);
    Serial.print(" mm | imu a=");
    Serial.print(currentSensors.imu.ax, 2);
    Serial.print(",");
    Serial.print(currentSensors.imu.ay, 2);
    Serial.print(",");
    Serial.print(currentSensors.imu.az, 2);
    Serial.print(" | faults M/U/I=");
    Serial.print(systemFaults.matrixSensor_fail);
    Serial.print("/");
    Serial.print(systemFaults.ultrasonic_fail);
    Serial.print("/");
    Serial.println(systemFaults.imu_fail);

    uint8_t hapticBits = hapticDriverStatusBits();
    Serial.print("HAPTIC_INIT bits=0x");
    Serial.print(hapticBits, HEX);
    Serial.print(" (8x8=");
    Serial.print((hapticBits & 0x10) ? "1" : "0");
    Serial.print(", right=");
    Serial.print((hapticBits & 0x20) ? "1" : "0");
    Serial.print(", left=");
    Serial.print((hapticBits & 0x40) ? "1" : "0");
    Serial.println(")");
}

void setup() {
    // === STEP 0: Bare minimum hardware check — runs before any sensor init ===
    // If you feel haptic pulses and serial output, the board and USB serial are alive.
    // Each subsequent step is gated so we can pinpoint any init that crashes.
    pinMode(HAPTIC_TOP_PIN, OUTPUT);   // GPIO18 = D9
    pinMode(HAPTIC_LEFT_PIN, OUTPUT);  // GPIO21 = D10
    pinMode(HAPTIC_RIGHT_PIN, OUTPUT); // GPIO38 = D11

    // Pulse all three directional haptic channels as "I am alive" signal.
    for (int i = 0; i < 2; i++) {
        digitalWrite(HAPTIC_TOP_PIN, HIGH);
        digitalWrite(HAPTIC_LEFT_PIN, HIGH);
        digitalWrite(HAPTIC_RIGHT_PIN, HIGH);
        delay(250);
        digitalWrite(HAPTIC_TOP_PIN, LOW);
        digitalWrite(HAPTIC_LEFT_PIN, LOW);
        digitalWrite(HAPTIC_RIGHT_PIN, LOW);
        delay(250);
    }

    Serial.begin(SERIAL_BAUD_RATE);
    delay(1500);
    Serial.println("=== BOOT OK: Serial alive ===");
    Serial.flush();

#if BOOT_MINIMAL_MODE
    Serial.println("=== BOOT_MINIMAL_MODE active: skipping all module init ===");
    Serial.flush();
    return;
#endif

    // === STEP 1: I2C mux ===
    Serial.println("[1] muxInit...");
    Serial.flush();
    muxInit();
    Serial.println("[1] muxInit OK");
    Serial.flush();

    // === STEP 2: Mode config ===
    Serial.println("[2] setMode...");
    Serial.flush();
    setMode(NORMAL);
    Serial.println("[2] setMode OK");
    Serial.flush();

#if ENABLE_BLE
    Serial.println("[2.5] bleInit...");
    Serial.flush();
    bleInit();
    Serial.println("[2.5] bleInit OK");
    Serial.flush();
#endif

    // === STEP 3: Sensors (IMU + ultrasonic + 8x8) ===
    Serial.println("[3] sensorsInit...");
    Serial.flush();
    sensorsInit();
    Serial.println("[3] sensorsInit OK");
    Serial.flush();

    // === STEP 4: Actuators ===
    Serial.println("[4] responsesInit...");
    Serial.flush();
    responsesInit();
    Serial.println("[4] responsesInit OK");
    Serial.flush();

    Serial.println("=== Setup complete — entering loop ===");
    Serial.flush();
}

void loop() {
    unsigned long now = millis();

#if BOOT_MINIMAL_MODE
    static unsigned long lastBlink = 0;
    static bool blinkState = false;
    if (now - lastBlink > 250) {
        lastBlink = now;
        blinkState = !blinkState;
        digitalWrite(HAPTIC_TOP_PIN, blinkState ? HIGH : LOW);
        digitalWrite(HAPTIC_LEFT_PIN, blinkState ? HIGH : LOW);
        digitalWrite(HAPTIC_RIGHT_PIN, blinkState ? HIGH : LOW);
        if (DEBUG_MODE) Serial.println("BOOT_MINIMAL_MODE loop alive");
    }
    return;
#endif

#if ISOLATED_SENSOR_TEST_MODE
    if (now - lastIMUUpdate > modeConfig.imuInterval) {
        updateIMU();
        lastIMUUpdate = now;
    }

    if (now - lastUltrasonicUpdate > modeConfig.ultrasonicInterval) {
        updateUltrasonic();
        lastUltrasonicUpdate = now;
    }

    if (now - lastMatrixSensorUpdate > modeConfig.matrixSensorInterval) {
        updateMatrixSensor();
        lastMatrixSensorUpdate = now;
    }

    // Keep IMU fault recovery active in isolated mode as well.
    checkFaults();

    fuseSituations();

    // Preserve IMU emergency behavior while staying in isolated sensor set.
    if (currentSituation == FALL_DETECTED || systemFaults.imu_fail) {
        if (currentMode != EMERGENCY) {
            setMode(EMERGENCY);
            currentEmergencyType = (currentSituation == FALL_DETECTED) ?
                                 EMERGENCY_FALL : EMERGENCY_SENSOR_FAIL;
            if (DEBUG_MODE) Serial.println("EMERGENCY MODE: Fall/IMU failure detected (isolated)");
        }
    } else if (currentMode == EMERGENCY &&
               currentSituation != FALL_DETECTED &&
               !systemFaults.imu_fail) {
        setMode(NORMAL);
        currentEmergencyType = EMERGENCY_NONE;
        emergencyActive = false;
        if (DEBUG_MODE) Serial.println("EMERGENCY CLEARED: returning to isolated normal mode");
    }

    handleResponses();

#if ENABLE_BLE
    blePoll();
    if (now - lastTelemetryUpdate > 200) {
        updateBLETelemetry();
        lastTelemetryUpdate = now;
    }
#endif

    printIsolatedSensorDebug(now);
    return;
#endif

    // === BATTERY MONITORING (Power Management Core) ===
    if (now - lastBatteryCheck > modeConfig.batteryCheckInterval) {
        updateBatteryMonitor();  // Enhanced battery health tracking
        currentSensors.batteryLevel = batteryStatus.percentage;
        
        // Debug output periodically (comprehensive battery metrics)
        debugBatteryMetrics();
        
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
    if (now - lastMatrixSensorUpdate > modeConfig.matrixSensorInterval) {
        updateMatrixSensor();
        lastMatrixSensorUpdate = now;
    }

    // Pulse Sensor: Heart rate monitoring
    if (now - lastPulseUpdate > modeConfig.pulseInterval) {
        updatePulse();
        lastPulseUpdate = now;
    }

    // Light Sensor: Ambient illumination level detection
    if (now - lastLightUpdate > LIGHT_SENSOR_UPDATE_INTERVAL) {
        lightSensorUpdate();
        lightStatus.lux = ambientLux;
        lightStatus.is_low_light = lowLightDetected;
        if (DEBUG_MODE && lightStatus.is_low_light) {
            Serial.print("Low-light condition detected: ");
            Serial.print(lightStatus.lux);
            Serial.println(" lux");
        }
        lastLightUpdate = now;
    }

    // === SLEEP MANAGEMENT ===
    if (now - lastSleepCheck > 1000) {
        updateSleepManager();
        lastSleepCheck = now;
    }

    // === FAULT DETECTION ===
    checkFaults();

    // === SITUATION FUSION ===
    fuseSituations();

    // === EMERGENCY MODE CONTROL (Highest Priority) ===
    // PRIORITY 1: FALL DETECTION triggers EMERGENCY (user safety critical)
    if (currentSituation == FALL_DETECTED || systemFaults.imu_fail) {
        if (currentMode != EMERGENCY) {
            setMode(EMERGENCY);
            currentEmergencyType = (currentSituation == FALL_DETECTED) ?
                                 EMERGENCY_FALL : EMERGENCY_SENSOR_FAIL;
            if (DEBUG_MODE) Serial.println("EMERGENCY MODE: Fall/IMU failure detected");
        }
    }
    // PRIORITY 2: HIGH_STRESS (close obstacle + abnormal HR) transitions to HIGH_STRESS mode
    // Note: HIGH_STRESS is NOT emergency-level but requires higher sensor sampling + faster BLE
    else if (currentSituation == HIGH_STRESS_EVENT) {
        if (currentMode != HIGH_STRESS && currentMode != EMERGENCY) {
            setMode(HIGH_STRESS);
            currentEmergencyType = EMERGENCY_HIGH_STRESS;
            if (DEBUG_MODE) Serial.println("HIGH_STRESS MODE: Close obstacle + abnormal heart rate");
        }
    }
    // PRIORITY 3: Exit HIGH_STRESS when threat clears (but stay above NORMAL if battery allows)
    else if (currentMode == HIGH_STRESS &&
             currentSituation != HIGH_STRESS_EVENT) {
        setMode(currentSensors.batteryLevel < BATTERY_LOW_THRESHOLD ? LOW_POWER : NORMAL);
        currentEmergencyType = EMERGENCY_NONE;
        if (DEBUG_MODE) Serial.println("HIGH_STRESS CLEARED: Returning to normal operation");
    }
    // PRIORITY 4: Exit emergency mode when situation clears
    else if (currentMode == EMERGENCY &&
             currentSituation != FALL_DETECTED &&
             !systemFaults.imu_fail) {
        // Exit emergency mode when fall situation clears
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
    if (ENABLE_BLE && now - lastTelemetryUpdate > telemetryInterval) {
        updateBLETelemetry();
        lastTelemetryUpdate = now;
    }
}