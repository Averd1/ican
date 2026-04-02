/**
 * sensors.cpp — Unified Sensor Implementation
 */

#include "sensors.h"
#include <Adafruit_LSM6DSOX.h>
#include <Arduino.h>
#include <PulseSensorPlayground.h>
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

// ---------------------------------------------------------------------------
// Fall detection — two-phase state machine
// Phase 1: FREE_FALL — accel magnitude drops below FREE_FALL_G for ≥80ms
// Phase 2: IMPACT    — accel magnitude spikes above IMPACT_G within 500ms
// Phase 3: CONFIRMED — hold fallDetected=true for FALL_HOLD_MS then reset
// ---------------------------------------------------------------------------
constexpr float FREE_FALL_G   = 5.0f;    // m/s² (≈0.5g) — low-G entry threshold
constexpr float IMPACT_G      = 20.0f;   // m/s² (≈2g)   — impact entry threshold
constexpr unsigned long FREE_FALL_MIN_MS = 80;    // must stay low-G for 80ms
constexpr unsigned long IMPACT_WINDOW_MS = 500;   // impact must follow within 500ms
constexpr unsigned long FALL_HOLD_MS     = 10000; // hold fall alert for 10 seconds

enum FallState { FALL_IDLE, FALL_FREE_FALL, FALL_IMPACT, FALL_CONFIRMED };
static FallState fallState = FALL_IDLE;
static unsigned long fallStateEnteredMs = 0;  // millis() when we entered current state
static bool fallDetectedGlobal = false;

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

// ===========================================================================
// Pulse Sensor — PulseSensor Playground library (WorldFamousElectronics)
// Hardware: PulseSensor Amped on analog pin A0, 3.3V on Nano ESP32
// Threshold 2000 is calibrated for ESP32 ADC range (verified working).
// ===========================================================================

// No delay() used — library handles 2ms sampling internally via micros().
// Call updatePulseSensor() every loop() iteration; it is a no-op until 2ms pass.

static PulseSensorPlayground pulseSensor;
static PulseData pulseResult = {0, false};
static unsigned long pulseLastBeatMs  = 0;
static unsigned long pulseLastDebugMs = 0;

// BPM is considered stale if no beat detected for 3 seconds
constexpr unsigned long PULSE_STALE_MS = 3000;

// Threshold tuned for ESP32 12-bit ADC (matches verified standalone firmware)
constexpr int PULSE_THRESHOLD = 2000;

void initPulseSensor(uint8_t pin) {
  pulseSensor.analogInput(pin);
  pulseSensor.setThreshold(PULSE_THRESHOLD);

  if (pulseSensor.begin()) {
    Serial.printf("[HR] PulseSensor ready on pin %d, threshold=%d\n",
                  pin, PULSE_THRESHOLD);
  } else {
    Serial.println("[HR] WARNING: PulseSensor.begin() failed — check wiring on A0");
  }
}

void updatePulseSensor() {
  // sawStartOfBeat() drives the library's internal 2ms sampling.
  // Returns true only on a confirmed beat — safe to call every loop().
  if (pulseSensor.sawStartOfBeat()) {
    int bpm = pulseSensor.getBeatsPerMinute();
    pulseLastBeatMs = millis();

    // Clamp to physiologically plausible range before storing
    if (bpm >= 40 && bpm <= 200) {
      pulseResult.bpm   = (uint8_t)bpm;
      pulseResult.valid = true;
    }

    Serial.printf("[HR] Beat! BPM: %d\n", bpm);
  }

  // Invalidate if no beat received within stale window (sensor removed / bad contact)
  if (pulseResult.valid && (millis() - pulseLastBeatMs) > PULSE_STALE_MS) {
    pulseResult.bpm   = 0;
    pulseResult.valid = false;
    Serial.println("[HR] Signal lost — no beat for 3s");
  }

  // Periodic status log every 2 seconds for debugging
  unsigned long now = millis();
  if ((now - pulseLastDebugMs) >= 2000) {
    pulseLastDebugMs = now;
    Serial.printf("[HR] BPM: %d, Valid: %s, Signal: %d\n",
      pulseResult.bpm,
      pulseResult.valid ? "YES" : "NO",
      pulseSensor.getLatestSample());
  }
}

PulseData getPulseData() {
  return pulseResult;
}

// ===========================================================================

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

  // Fall detection — two-phase state machine
  // Use squared comparisons to avoid sqrt() (problematic on Windows builds)
  float accelMagSq = (data.accelX * data.accelX) +
                     (data.accelY * data.accelY) +
                     (data.accelZ * data.accelZ);
  unsigned long now = millis();

  switch (fallState) {
    case FALL_IDLE:
      if (accelMagSq < (FREE_FALL_G * FREE_FALL_G)) {
        fallState = FALL_FREE_FALL;
        fallStateEnteredMs = now;
        Serial.printf("[FALL] IDLE → FREE_FALL (accelMagSq=%.2f)\n", accelMagSq);
      }
      break;

    case FALL_FREE_FALL:
      if (accelMagSq >= (FREE_FALL_G * FREE_FALL_G)) {
        // Left low-G zone without enough duration — reset
        if ((now - fallStateEnteredMs) < FREE_FALL_MIN_MS) {
          fallState = FALL_IDLE;
          Serial.println("[FALL] FREE_FALL → IDLE (too short)");
          break;
        }
        // Stayed in low-G long enough — now watch for impact
        fallState = FALL_IMPACT;
        fallStateEnteredMs = now;
        Serial.printf("[FALL] FREE_FALL → IMPACT (window open, accelMagSq=%.2f)\n", accelMagSq);
      } else if ((now - fallStateEnteredMs) > IMPACT_WINDOW_MS) {
        // Stayed low-G too long (device just lying still?) — reset
        fallState = FALL_IDLE;
        Serial.println("[FALL] FREE_FALL → IDLE (timeout, no impact)");
      }
      break;

    case FALL_IMPACT:
      if (accelMagSq > (IMPACT_G * IMPACT_G)) {
        // Impact detected → confirmed fall
        fallState = FALL_CONFIRMED;
        fallStateEnteredMs = now;
        fallDetectedGlobal = true;
        Serial.printf("[FALL] IMPACT → CONFIRMED (accelMagSq=%.2f) — FALL ALERT!\n", accelMagSq);
      } else if ((now - fallStateEnteredMs) > IMPACT_WINDOW_MS) {
        // No impact within window — false alarm
        fallState = FALL_IDLE;
        Serial.println("[FALL] IMPACT → IDLE (no impact in window)");
      }
      break;

    case FALL_CONFIRMED:
      if ((now - fallStateEnteredMs) >= FALL_HOLD_MS) {
        fallState = FALL_IDLE;
        fallDetectedGlobal = false;
        Serial.println("[FALL] CONFIRMED → IDLE (hold expired)");
      }
      break;
  }

  data.fallDetected = fallDetectedGlobal;

  return data;
}
