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
    LOW_POWER,     // 15-hour target: battery fallback when <20% (5 Hz sensors, no LED)
    HIGH_STRESS,   // 4-hour peak: close obstacle + abnormal HR (30-50 Hz sensors, max haptics)
    EMERGENCY      // Fall/critical: <60s duration, 100+ Hz sensors, max telemetry, NO haptic
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
    unsigned long lastRecoveryAttempt;
};

// === BLE TELEMETRY PACKET (v4: full offline sensor validation) ===
// Includes battery, mode, pulse BPM/raw, IMU acceleration, and distance channels.
struct __attribute__((packed)) TelemetryPacket {
    uint8_t version;           // Protocol version = 4
    uint8_t batteryPercent;    // Battery level (0-100)
    uint8_t currentMode;       // NORMAL=0, LOW_POWER=1, HIGH_STRESS=2, EMERGENCY=3
    uint8_t heartBPM;          // Heart rate (0-255)
    uint8_t flags;             // bit0=fall, bit1=high_stress, bit2=obstacle_near, bit3=obstacle_imminent
    uint8_t sensorStatus;      // bit0=imu_valid, bit1=ultra_left_valid, bit2=ultra_right_valid, bit3=matrix_head_valid, bit4=matrix_waist_valid, bit5=pulse_valid, bit6=battery_valid
    int16_t imuAxCms2;         // IMU accel X scaled by 100 (m/s^2 -> centi-m/s^2)
    int16_t imuAyCms2;         // IMU accel Y scaled by 100
    int16_t imuAzCms2;         // IMU accel Z scaled by 100
    uint16_t ultrasonicLeftMm; // Left ultrasonic distance (mm)
    uint16_t ultrasonicRightMm;// Right ultrasonic distance (mm)
    uint16_t matrixHeadMm;     // 8x8 head-zone distance (mm), 0xFFFF when unavailable
    uint16_t matrixWaistMm;    // 8x8 waist-zone distance (mm), 0xFFFF when unavailable
    uint16_t heartRaw;         // Raw pulse analog sample
};
// Total: 22 bytes

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