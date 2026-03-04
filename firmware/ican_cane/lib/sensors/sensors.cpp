/**
 * sensors.cpp — Unified Sensor Implementation
 */

#include "sensors.h"
#include <Adafruit_LSM6DSOX.h>
#include <Arduino.h>
#include <Wire.h>

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------
static uint8_t pinLeftTrig, pinLeftEcho;
static uint8_t pinRightTrig, pinRightEcho;
static Adafruit_LSM6DSOX imu;
static bool imuReady = false;

// TF Luna I²C address (default)
constexpr uint8_t TF_LUNA_ADDR = 0x10;

// Fall detection threshold (m/s² — near free-fall)
constexpr float FALL_THRESHOLD = 3.0f;

// ---------------------------------------------------------------------------
// Ultrasonic helper
// ---------------------------------------------------------------------------
static float readUltrasonic(uint8_t trigPin, uint8_t echoPin) {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);

  unsigned long duration = pulseIn(echoPin, HIGH, 30000); // 30ms timeout
  if (duration == 0)
    return -1.0f;

  // Speed of sound ≈ 0.0343 cm/µs, round-trip → divide by 2
  return (duration * 0.0343f) / 2.0f;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void initSensors(uint8_t leftTrig, uint8_t leftEcho, uint8_t rightTrig,
                 uint8_t rightEcho) {
  // Ultrasonic pins
  pinLeftTrig = leftTrig;
  pinLeftEcho = leftEcho;
  pinRightTrig = rightTrig;
  pinRightEcho = rightEcho;

  pinMode(pinLeftTrig, OUTPUT);
  pinMode(pinLeftEcho, INPUT);
  pinMode(pinRightTrig, OUTPUT);
  pinMode(pinRightEcho, INPUT);

  Serial.println("[Sensors] Ultrasonic pins configured.");

  // IMU init (I²C mux must be on IMU channel before calling)
  if (imu.begin_I2C()) {
    imuReady = true;
    imu.setAccelRange(LSM6DS_ACCEL_RANGE_4_G);
    imu.setGyroRange(LSM6DS_GYRO_RANGE_250_DPS);
    imu.setAccelDataRate(LSM6DS_RATE_104_HZ);
    imu.setGyroDataRate(LSM6DS_RATE_104_HZ);
    Serial.println("[Sensors] LSM6DSOX IMU initialized.");
  } else {
    Serial.println("[Sensors] WARNING: LSM6DSOX not found.");
  }

  Serial.println("[Sensors] Init complete.");
}

float readUltrasonicLeft() { return readUltrasonic(pinLeftTrig, pinLeftEcho); }

float readUltrasonicRight() {
  return readUltrasonic(pinRightTrig, pinRightEcho);
}

float readLidar() {
  // TF Luna I²C read: request 2 bytes (distance low, distance high)
  Wire.beginTransmission(TF_LUNA_ADDR);
  Wire.write(0x01); // Register: distance low byte
  Wire.write(0x02); // + distance high byte
  if (Wire.endTransmission(false) != 0) {
    return -1.0f;
  }

  Wire.requestFrom(TF_LUNA_ADDR, (uint8_t)2);
  if (Wire.available() < 2)
    return -1.0f;

  uint8_t low = Wire.read();
  uint8_t high = Wire.read();
  return static_cast<float>((high << 8) | low); // cm
}

ImuData readIMU() {
  ImuData data = {};
  if (!imuReady)
    return data;

  sensors_event_t accel, gyro, temp;
  imu.getEvent(&accel, &gyro, &temp);

  data.accelX = accel.acceleration.x;
  data.accelY = accel.acceleration.y;
  data.accelZ = accel.acceleration.z;
  data.gyroX = gyro.gyro.x;
  data.gyroY = gyro.gyro.y;
  data.gyroZ = gyro.gyro.z;

  // Simple yaw estimation from gyro Z integration (placeholder)
  // TODO (Task 4.1): Replace with proper complementary/Madgwick filter
  static float yawAccum = 0.0f;
  yawAccum += data.gyroZ * 0.05f; // dt ≈ 50ms
  data.yaw = yawAccum;

  // Fall detection: magnitude squared of accel vector near zero = free-fall
  // Optimization: use mag squared rather than sqrt() since we just compare to a
  // threshold
  float const FALL_THRESH_SQ = FALL_THRESHOLD * FALL_THRESHOLD;
  float accelMagSq = (data.accelX * data.accelX) + (data.accelY * data.accelY) +
                     (data.accelZ * data.accelZ);

  data.fallDetected = (accelMagSq < FALL_THRESH_SQ);

  return data;
}
