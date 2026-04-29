/*
 * ProtoSmartCane - Global State Declarations
 * All extern variables and shared data structures
 */

#pragma once

#include "config.h"
#include "power_profile.h"
#include <Arduino.h>

// === SYSTEM MODES ===
enum SystemMode {
    NORMAL,        // 8-hour target: balanced responsive operation (20-30 Hz sensors)
    LOW_POWER,     // 15-hour target: battery fallback when <20% (5 Hz sensors, reduced haptics)
    HIGH_STRESS,   // 4-hour peak: close obstacle + abnormal HR (30-50 Hz sensors, max haptics)
    EMERGENCY      // Fall/critical: <60s duration, 100+ Hz sensors, max telemetry, max haptics
};

enum EmergencyType {
    EMERGENCY_NONE,
    EMERGENCY_FALL,
    EMERGENCY_HIGH_STRESS,
    EMERGENCY_SENSOR_FAIL
};

// === OBSTACLE ZONES ===
enum ObstacleZone {
    OBSTACLE_NONE,
    OBSTACLE_FAR,
    OBSTACLE_NEAR,
    OBSTACLE_IMMINENT
};

// === SITUATION DETECTION ===
enum Situation {
    NONE,
    OBJECT_FAR,        // Distant obstacle detected
    OBJECT_NEAR,       // Close obstacle detected
    OBJECT_IMMINENT,   // Very close obstacle - collision imminent
    FALL_DETECTED,     // Fall detected via IMU
    HIGH_STRESS_EVENT  // High stress: close obstacle + abnormal heart rate
};

// === SENSOR DATA STRUCTURES ===
struct IMUData {
    float ax, ay, az;  // Acceleration (m/s²)
    float gx, gy, gz;  // Gyroscope (°/s)
};

struct SensorData {
    IMUData imu;
    uint16_t ultrasonicDistances[NUM_ULTRASONIC_SENSORS];  // mm
    uint16_t matrixSensorDistance;     // mm
    uint16_t matrixSensorHeadDistance; // mm - closest object in head zone
    uint16_t matrixSensorWaistDistance; // mm - closest object in waist/front zone
    bool matrixSensorHeadDetected;     // object present in the top half of the matrix
    bool matrixSensorWaistDetected;    // object present in lower-middle front of the matrix
    int heartBPM;              // beats per minute
    int heartRaw;              // raw analog reading
    bool pulseDetected;        // beat detection flag
    bool heartAbnormal;        // abnormal heart rate flag
    int batteryLevel;          // battery percentage (0-100)
    ObstacleZone ultrasonicZones[NUM_ULTRASONIC_SENSORS];
    ObstacleZone matrixSensorZone;
};

struct ModeConfig {
    unsigned long imuInterval;
    unsigned long ultrasonicInterval;
    unsigned long matrixSensorInterval;
    unsigned long pulseInterval;
    unsigned long batteryCheckInterval;
};

struct FaultState {
    bool imu_fail;
    bool ultrasonic_fail;
    bool matrixSensor_fail;
    bool heart_fail;
    bool mux_fail;
    unsigned long lastRecoveryAttempt;
};

// === BLE TELEMETRY PACKET ===
// App-compatible 6-byte cane telemetry packet. The mobile app expects the
// flags byte first, with bit0 indicating fall detected.
struct __attribute__((packed)) TelemetryPacket {
    uint8_t flags;             // bit0=fall, bit1=pulse_valid
    uint8_t heartBPM;          // Heart rate (0-255)
    uint8_t batteryPercent;    // Battery level (0-100)
    int16_t yawAngleTenths;    // degrees * 10; reserved as 0 until yaw is supported
    uint8_t reserved;          // reserved for app protocol compatibility
};
// Total: 6 bytes

// === LIGHT SENSOR STATUS (NEW) ===
struct LightStatus {
    uint16_t lux;
    bool is_low_light;
};

// === GLOBAL STATE VARIABLES ===
extern SystemMode currentMode;
extern ModeConfig modeConfig;
extern Situation currentSituation;
extern EmergencyType currentEmergencyType;
extern SensorData currentSensors;
extern FaultState systemFaults;

// Emergency state tracking
extern bool emergencyActive;
extern unsigned long emergencyStartTime;

// Sensor state flags
extern bool obstacleNear;
extern bool obstacleImminent;
extern bool ultrasonicNear;
extern bool ultrasonicImminent;
extern bool imuFallDetected;
extern bool imuOrientationOk;

// Timing variables
extern unsigned long lastIMUUpdate;
extern unsigned long lastUltrasonicUpdate;
extern unsigned long lastMatrixSensorUpdate;
extern unsigned long lastPulseUpdate;
extern unsigned long lastBatteryCheck;
extern unsigned long lastTelemetryUpdate;
extern unsigned long lastSleepCheck;

// Sequence numbering for BLE
extern uint16_t telemetrySequence;

// === NEW STATE VARIABLES (Power Management & Sensing) ===
extern LightStatus lightStatus;

// Emergency state history (for safe sleep transitions)
extern unsigned long emergencyHistory[STATE_HISTORY_SIZE];
extern uint8_t emergencyHistoryIndex;
