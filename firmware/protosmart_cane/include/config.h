/*
 * ProtoSmartCane - Centralized Configuration
 * All tuning parameters, constants, and hardware definitions
 */

#pragma once

// === HARDWARE PIN DEFINITIONS ===
#define BUZZER_PIN 9
#define LED_PIN 6
#define BATTERY_PIN A0

// === BATTERY MONITORING ===
#define BATTERY_R1 10000.0f    // Voltage divider resistor 1 (10k)
#define BATTERY_R2 3300.0f     // Voltage divider resistor 2 (3.3k)
#define BATTERY_VREF 3.3f      // ESP32 ADC reference voltage
#define BATTERY_MAX_V 4.2f     // LiPo max voltage
#define BATTERY_MIN_V 3.0f     // LiPo min voltage
#define BATTERY_LOW_THRESHOLD 20   // % - trigger low power mode
#define BATTERY_RECOVERY_THRESHOLD 30  // % - return to normal mode

// === I2C ADDRESSES ===
#define MUX_ADDR 0x70              // PCA9548A I2C multiplexer
#define LIDAR_I2C_ADDR 0x10        // TF Luna LiDAR
#define ULTRASONIC_I2C_ADDR 0x11   // URM37 Ultrasonic
#define IMU_I2C_ADDR 0x6A          // LSM6DSOX IMU (primary address)

// === MUX CHANNEL ASSIGNMENTS ===
#define LIDAR_CHANNEL 0
#define ULTRASONIC_CHANNEL 1
#define IMU_CHANNEL 2

// === FALL DETECTION PARAMETERS ===
#define FALL_FREEFALL_THRESHOLD 4.0f     // m/s² (~0.4g) - start of free fall
#define FALL_IMPACT_THRESHOLD 25.0f      // m/s² (~2.5g) - impact detection
#define FALL_IMPACT_WINDOW 500           // ms - max time between freefall and impact
#define FALL_INACTIVITY_TIMEOUT 2000     // ms - inactivity detection
#define FALL_COOLDOWN 5000               // ms - prevent fall spam detection

// === OBSTACLE DETECTION THRESHOLDS ===
#define OBSTACLE_NEAR_MM 500             // mm - near obstacle warning
#define OBSTACLE_IMMINENT_MM 200         // mm - imminent collision alert

// === ULTRASONIC CONFIGURATION ===
#define NUM_ULTRASONIC_SENSORS 2         // Number of ultrasonic sensors
#define ULTRASONIC_MAX_RANGE_MM 800      // Maximum reliable range

// === HEART RATE MONITORING ===
#define HEART_PIN A0
#define HEART_THRESHOLD 2000             // PulseSensor threshold
#define HEART_ABNORMAL_HIGH_BPM 120      // High heart rate threshold
#define HEART_ABNORMAL_LOW_BPM 50        // Low heart rate threshold

// === AMBIENT LIGHT SENSOR ===
#define LOW_LIGHT_THRESHOLD_LUX 100      // lux - brightness below which LED enables
#define LIGHT_SENSOR_UPDATE_INTERVAL 1000 // ms - update light sensor reading

// === LED ILLUMINATION ===
#define LED_ILLUMINATION_PIN 11          // GPIO pin for high-power LED PWM
#define LED_BRIGHTNESS_LOW_LIGHT 150     // Default brightness in low-light
#define LED_BRIGHTNESS_OBSTACLE 200      // Brightness for obstacle warning
#define LED_BRIGHTNESS_EMERGENCY 255     // Full brightness during emergency

// === HAPTIC DRIVER (DRV2605L) ===
#define HAPTIC_PIN 12                    // GPIO for haptic trigger (if PWM-only)
#define HAPTIC_I2C_DRIVER true           // Use I2C driver vs GPIO PWM

// === EMERGENCY SYSTEM ===
#define EMERGENCY_DURATION_MS 30000      // 30 seconds max emergency alerts
#define EMERGENCY_INITIAL_INTENSITY_MS 3000  // 3 seconds of max intensity

// === POWER MODE SAMPLING RATES (ms intervals) ===
#define NORMAL_IMU_INTERVAL 50           // 20 Hz
#define NORMAL_ULTRASONIC_INTERVAL 100   // 10 Hz
#define NORMAL_LIDAR_INTERVAL 100        // 10 Hz
#define NORMAL_PULSE_INTERVAL 200        // 5 Hz
#define NORMAL_BATTERY_CHECK_INTERVAL 5000  // 5 seconds

#define LOW_POWER_IMU_INTERVAL 200       // 5 Hz
#define LOW_POWER_ULTRASONIC_INTERVAL 500 // 2 Hz
#define LOW_POWER_LIDAR_INTERVAL 500     // 2 Hz
#define LOW_POWER_PULSE_INTERVAL 1000    // 1 Hz
#define LOW_POWER_BATTERY_CHECK_INTERVAL 10000  // 10 seconds

#define EMERGENCY_IMU_INTERVAL 10        // 100 Hz
#define EMERGENCY_ULTRASONIC_INTERVAL 50 // 20 Hz
#define EMERGENCY_LIDAR_INTERVAL 50      // 20 Hz
#define EMERGENCY_PULSE_INTERVAL 50      // 20 Hz
#define EMERGENCY_BATTERY_CHECK_INTERVAL 1000  // 1 second

// === RESPONSE SYSTEM TIMING ===
#define RESPONSE_PULSE_FAR_MS 300        // Slow pulse for distant obstacles
#define RESPONSE_PULSE_NEAR_MS 150       // Medium pulse for near obstacles
#define RESPONSE_PULSE_IMMINENT_MS 50    // Fast pulse for imminent obstacles
#define RESPONSE_PULSE_STRESS_MS 25      // Very fast pulse for high stress
#define RESPONSE_PULSE_FALL_MS 100       // Pulsed fall alert (not continuous)

// === LED BRIGHTNESS LEVELS ===
#define LED_OFF 0
#define LED_DIM 100
#define LED_MEDIUM 180
#define LED_BRIGHT 255

// === SENSOR ERROR VALUES ===
#define SENSOR_ERROR_DISTANCE 0xFFFF     // Invalid distance reading
#define SENSOR_ERROR_HEART -1            // Invalid heart rate
#define SENSOR_ERROR_IMU NAN             // Invalid IMU reading

// === FAULT DETECTION ===
#define SENSOR_FAIL_THRESHOLD 5          // Consecutive failures before fault
#define SENSOR_RECOVERY_TIME_MS 2000     // Time to attempt recovery

// === BLE CONFIGURATION ===
#define BLE_DEVICE_NAME "ProtoSmartCane"
#define BLE_SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define BLE_CHARACTERISTIC_UUID "abcd1234-5678-5678-5678-abcd12345678"
#define BLE_TELEMETRY_VERSION 0x02    // v2: Simplified for battery calc on app

// === BLE TELEMETRY OPTIMIZATION ===
// The cane sends minimal data; the app calculates battery lifetime using this power profile:
//   NORMAL: 85 mA → 8 hours @ 660mAh
//   LOW_POWER: 50 mA → 13 hours @ 660mAh
//   EMERGENCY: 250 mA → 2.6 hours @ 660mAh (capped 30s)
//   CAUTIOUS_SLEEP: 30 mA → 22 hours @ 660mAh
//   DEEP_SLEEP: 10 mA → 66 hours @ 660mAh
//
// App telemetry input (5 bytes):
//   [battery_percent] [current_mode] [heart_rate] [flags] [reserved]
// App output:
//   Estimated runtime = 660mAh / current_power_in_mode × battery_percent / 100
//   Example: 85% battery in NORMAL mode → 85 / 100 × 8 hours = 6.8 hours remaining

// === SERIAL DEBUGGING ===
#define SERIAL_BAUD_RATE 115200
#define DEBUG_MODE true  // Set to false for production