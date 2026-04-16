/*
 * ProtoSmartCane - Centralized Configuration
 * All tuning parameters, constants, and hardware definitions
 */

#pragma once

// === HARDWARE PIN DEFINITIONS ===
#define BUZZER_PIN A2           // Buzzer output (A2)
#define LED_PIN -1              // Legacy LED output disabled to avoid overlap with SDA2 bus
#define LED_HEAD_PIN 9          // NEW: Head zone LED (D9)
#define LED_LEFT_PIN 10         // NEW: Left zone LED (D10)
#define LED_RIGHT_PIN 11        // NEW: Right zone LED (D11)
#define LED_HAPTIC_FRONT_PIN 12 // Haptic mimic LED for 8x8 matrix front detection
#define LED_HAPTIC_LEFT_PIN 13  // Haptic mimic LED for left ultrasonic sensor
#define LED_HAPTIC_RIGHT_PIN A3 // Haptic mimic LED for right ultrasonic sensor (A3)
#define BATTERY_PIN A1          // Battery monitor on separate analog input from pulse sensor
#define HEART_PIN A0            // Pulse sensor input
#define PULSE_LED -1            // Optional pulse blink LED disabled for external wiring cleanup
#define LOW_BATTERY_PIN 8       // LB0 from PowerBoost low battery signal (D8)

// === SPI / I2C BUS PINS ===
// Nano ESP32 remapped pin API: A4=21, A5=22
#define I2C_SDA_PIN 21          // Primary SDA bus (A4)
#define I2C_SCL_PIN 22          // Primary SCL bus (A5)

// === ULTRASONIC PIN DEFINITIONS ===
#define ULTRASONIC_LEFT_ECHO_PIN 4   // Left ultrasonic ECHO (D4)
#define ULTRASONIC_LEFT_TRIG_PIN 5   // Left ultrasonic TRIG (D5)
#define ULTRASONIC_RIGHT_ECHO_PIN 2  // Right ultrasonic ECHO (D2)
#define ULTRASONIC_RIGHT_TRIG_PIN 3  // Right ultrasonic TRIG (D3)

// === I2C2 BUS PINS ===
// Schematic mapping: D6 -> SDA2, D7 -> SCL2
#define I2C2_SDA_PIN 6             // Secondary SDA2 bus (D6)
#define I2C2_SCL_PIN 7             // Secondary SCL2 bus (D7)
#define BATTERY_R1 10000.0f    // Voltage divider resistor 1 (10k)
#define BATTERY_R2 3300.0f     // Voltage divider resistor 2 (3.3k)
#define BATTERY_VREF 3.3f      // ESP32 ADC reference voltage
#define BATTERY_MAX_V 4.2f     // LiPo max voltage
#define BATTERY_MIN_V 3.0f     // LiPo min voltage
#define BATTERY_LOW_THRESHOLD 20   // % - trigger low power mode
#define BATTERY_RECOVERY_THRESHOLD 30  // % - return to normal mode

// === I2C ADDRESSES ===
#define MUX_ADDR 0x70              // PCA9548A I2C multiplexer
#define MATRIX_SENSOR_I2C_ADDR 0x33        // 8x8 matrix sensor on secondary I2C bus
#define IMU_I2C_ADDR 0x6A          // LSM6DSOX IMU (primary address)

// === MUX CHANNEL ASSIGNMENTS ===
#define MATRIX_SENSOR_CHANNEL 0
#define ULTRASONIC_CHANNEL 1
#define IMU_CHANNEL 2
#define LIGHT_CHANNEL 3
#define HAPTIC_CHANNEL 4

// === 8x8 MATRIX SENSOR CONFIGURATION ===
#define MATRIX_SENSOR_MAX_DISTANCE_MM 1500  // mm - ignore far readings beyond useful range
#define MATRIX_SENSOR_ZONE_THRESHOLD_MM 1000 // mm - use this for far obstacle classification

// === FALL DETECTION PARAMETERS ===
#define FALL_FREEFALL_THRESHOLD 4.0f     // m/s² (~0.4g) - start of free fall
#define FALL_IMPACT_THRESHOLD 25.0f      // m/s² (~2.5g) - impact detection
#define FALL_IMPACT_WINDOW 500           // ms - max time between freefall and impact
#define FALL_INACTIVITY_TIMEOUT 2000     // ms - inactivity detection
#define FALL_COOLDOWN 5000               // ms - prevent fall spam detection

// === OBSTACLE DETECTION THRESHOLDS ===
#define OBSTACLE_FAR_MM 1000             // mm - far obstacle detection
#define OBSTACLE_NEAR_MM 500             // mm - near obstacle warning
#define OBSTACLE_IMMINENT_MM 200         // mm - imminent collision alert

// === ULTRASONIC CONFIGURATION ===
#define NUM_ULTRASONIC_SENSORS 2         // Number of ultrasonic sensors
#define ULTRASONIC_MAX_RANGE_MM 800      // Maximum reliable range

// === HEART RATE MONITORING ===
#define HEART_THRESHOLD 2000             // PulseSensor threshold
#define HEART_ABNORMAL_HIGH_BPM 120      // High heart rate threshold
#define HEART_ABNORMAL_LOW_BPM 50        // Low heart rate threshold

// === AMBIENT LIGHT SENSOR ===
#define LOW_LIGHT_THRESHOLD_LUX 100      // lux - brightness below which LED enables
#define LIGHT_SENSOR_UPDATE_INTERVAL 1000 // ms - update light sensor reading

// === LED ILLUMINATION ===
#define BOOST_ENABLE_PIN 23              // Boost converter EN control (A6)
#define LED_ILLUMINATION_PIN 24          // High-power LED PWM output (A7)
#define LED_BRIGHTNESS_LOW_LIGHT 150     // Default brightness in low-light
#define LED_BRIGHTNESS_OBSTACLE 200      // Brightness for obstacle warning
#define LED_BRIGHTNESS_EMERGENCY 255     // Full brightness during emergency

// === HAPTIC DRIVER (DRV2605L) ===
#define HAPTIC_PIN 255                   // Unused in current DRV2605L I2C configuration
#define HAPTIC_I2C_DRIVER true           // Use I2C driver vs GPIO PWM

// === EMERGENCY SYSTEM ===
#define EMERGENCY_DURATION_MS 30000      // 30 seconds max emergency alerts
#define EMERGENCY_INITIAL_INTENSITY_MS 3000  // 3 seconds of max intensity

// === POWER MODE SAMPLING RATES (ms intervals) ===
// NORMAL MODE: 20 Hz IMU, 15 Hz ultrasonic, 20 Hz LiDAR, 10 Hz pulse
#define NORMAL_IMU_INTERVAL 50           // 20 Hz  (responsive motion + fall detection)
#define NORMAL_ULTRASONIC_INTERVAL 67    // 15 Hz  (frequent proximity checks)
#define NORMAL_MATRIX_SENSOR_INTERVAL 50         // 20 Hz  (rapid forward updates)
#define NORMAL_PULSE_INTERVAL 100        // 10 Hz  (real-time stress capability)
#define NORMAL_BATTERY_CHECK_INTERVAL 2000  // 2 seconds (increased frequency)

// LOW_POWER MODE: 5 Hz all sensors (battery <20% fallback)
#define LOW_POWER_IMU_INTERVAL 200       // 5 Hz   (fall detection only)
#define LOW_POWER_ULTRASONIC_INTERVAL 200 // 5 Hz  (coarse checks)
#define LOW_POWER_MATRIX_SENSOR_INTERVAL 200     // 5 Hz   (sparse awareness)
#define LOW_POWER_PULSE_INTERVAL 500     // 2 Hz   (minimal overhead)
#define LOW_POWER_BATTERY_CHECK_INTERVAL 10000  // 10 seconds

// HIGH_STRESS MODE: 50 Hz IMU, 30 Hz ultrasonic/LiDAR, 20 Hz pulse (close obstacle + abnormal HR)
#define HIGH_STRESS_IMU_INTERVAL 20      // 50 Hz  (rapid threat detection)
#define HIGH_STRESS_ULTRASONIC_INTERVAL 33 // 30 Hz (very frequent proximity)
#define HIGH_STRESS_MATRIX_SENSOR_INTERVAL 33    // 30 Hz  (rapid threat updates)
#define HIGH_STRESS_PULSE_INTERVAL 50    // 20 Hz  (stress level tracking)
#define HIGH_STRESS_BATTERY_CHECK_INTERVAL 1000 // 1 second

// EMERGENCY MODE: 100+ Hz IMU, 40 Hz ultrasonic/LiDAR, 40 Hz pulse (fall detection, time-limited)
#define EMERGENCY_IMU_INTERVAL 10        // 100 Hz (maximum fall impact resolution)
#define EMERGENCY_ULTRASONIC_INTERVAL 25 // 40 Hz  (ground impact + environment)
#define EMERGENCY_MATRIX_SENSOR_INTERVAL 25      // 40 Hz  (detailed landing mapping)
#define EMERGENCY_PULSE_INTERVAL 25      // 40 Hz  (stress spike capture)
#define EMERGENCY_BATTERY_CHECK_INTERVAL 500  // 0.5 second

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
//   NORMAL: 85 mA → ~77 hours @ 6600mAh
//   LOW_POWER: 50 mA → ~118 hours @ 6600mAh
//   EMERGENCY: 250 mA → ~26 hours @ 6600mAh (capped 30s)
//   CAUTIOUS_SLEEP: 30 mA → ~198 hours @ 6600mAh
//   DEEP_SLEEP: 10 mA → ~594 hours @ 6600mAh
//
// App telemetry input (5 bytes):
//   [battery_percent] [current_mode] [heart_rate] [flags] [reserved]
// App output:
//   Estimated runtime = 4400mAh / current_power_in_mode × battery_percent / 100
//   Example: 85% battery in NORMAL mode → 85 / 100 × 47.6 hours = 40.46 hours remaining

// === SERIAL DEBUGGING ===
#define SERIAL_BAUD_RATE 115200
#define DEBUG_MODE true  // Set to false for production
#define ENABLE_BLE true  // Set false for local serial-only validation without BLE