/**
 * sensors.h — Unified Sensor Interface
 *
 * Abstracts the TF Luna LiDAR, 2x Ultrasonic sensors, and LSM6DSOX IMU
 * behind clean read functions. The I²C mux channel must be selected
 * before calling LiDAR or IMU functions.
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
 * Ultrasonic sensors use GPIO pins; LiDAR and IMU use I²C (mux-selected).
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
 * Read TF Luna LiDAR distance in centimeters.
 * I²C mux must be set to the LiDAR channel before calling.
 */
float readLidar();

/**
 * Read LSM6DSOX IMU data.
 * I²C mux must be set to the IMU channel before calling.
 */
ImuData readIMU();

#endif // SENSORS_H
