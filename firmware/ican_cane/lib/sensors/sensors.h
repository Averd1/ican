/**
 * sensors.h — Unified Sensor Interface
 *
 * Abstracts the DFRobot SEN0628 Matrix LiDAR, 2x Ultrasonic sensors,
 * and LSM6DSOX IMU behind clean read functions.
 * LiDAR and IMU both use Wire1 (D6=SDA, D7=SCL) directly — no mux.
 */

#ifndef SENSORS_H
#define SENSORS_H

#include <stdint.h>

/**
 * IMU reading data.
 */
struct ImuData {
  float accelX, accelY, accelZ; // m/s²
  float gyroX, gyroY, gyroZ;    // deg/s
  float yaw;                    // estimated yaw in degrees
  bool fallDetected;            // sudden free-fall flag
};

/**
 * Initialize all sensors.
 * Ultrasonic sensors use GPIO pins; LiDAR and IMU use Wire1 (D6/D7).
 */
void initSensors(uint8_t leftTrig, uint8_t leftEcho, uint8_t rightTrig,
                 uint8_t rightEcho);

/**
 * Read left ultrasonic sensor distance in centimeters.
 * Returns -1.0 if no echo received.
 */
float readUltrasonicLeft();

/**
 * Read right ultrasonic sensor distance in centimeters.
 * Returns -1.0 if no echo received.
 */
float readUltrasonicRight();

/**
 * Read DFRobot SEN0628 Matrix LiDAR — returns closest point distance in cm.
 * Uses Wire1 (D6/D7) directly at I2C address 0x33.
 */
float readLidar();

/**
 * Read LSM6DSOX IMU data.
 * Uses Wire1 (D6/D7) directly.
 */
ImuData readIMU();

// ===========================================================================
// Pulse (Heart Rate) Sensor
// ===========================================================================

/**
 * Heart rate measurement result.
 */
struct PulseData {
  uint8_t bpm;  // computed BPM (0 if not yet valid)
  bool valid;   // true when signal amplitude is good and BPM is in 40–200 range
};

/**
 * Initialize the pulse sensor on the given analog pin.
 * Call once in setup(). Pin must be 3.3V-safe (Nano ESP32 A0).
 */
void initPulseSensor(uint8_t pin);

/**
 * Update pulse sensor state at 500 Hz — call every loop() iteration.
 * Uses micros() internally; does not block.
 */
void updatePulseSensor();

/**
 * Return the latest computed heart rate data.
 */
PulseData getPulseData();

#endif // SENSORS_H
