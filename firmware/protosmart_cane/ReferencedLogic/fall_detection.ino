#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include <Adafruit_Sensor.h>

// ===== IMU OBJECT =====
Adafruit_LSM6DSOX imu;

// ===== SECOND I2C BUS =====
TwoWire I2C_2 = TwoWire(1);  // Bus 1

// ===== GLOBAL FALL FLAG =====
bool fallDetectedGlobal = false;

// ===== THRESHOLDS =====
#define FREE_FALL_THRESH 0.5
#define IMPACT_THRESH    2.5
#define GYRO_THRESH      180.0
#define FALL_WINDOW_MS   500
#define COOLDOWN_MS      2000

// ===== STATE MACHINE =====
enum FallState {
  NORMAL,
  FREE_FALL_DETECTED
};

FallState state = NORMAL;

// ===== TIMERS =====
unsigned long freeFallTime = 0;
unsigned long lastFallTime = 0;

// ===== DATA STRUCT =====
struct ImuData {
  float accelMag;
  float gyroMag;
};

// ===== READ IMU =====
ImuData readIMU() {
  ImuData data = {};

  sensors_event_t accel, gyro, temp;
  imu.getEvent(&accel, &gyro, &temp);

  float ax = accel.acceleration.x / 9.81;
  float ay = accel.acceleration.y / 9.81;
  float az = accel.acceleration.z / 9.81;

  float gx = gyro.gyro.x * 57.2958;
  float gy = gyro.gyro.y * 57.2958;
  float gz = gyro.gyro.z * 57.2958;

  data.accelMag = sqrt(ax * ax + ay * ay + az * az);
  data.gyroMag  = sqrt(gx * gx + gy * gy + gz * gz);

  return data;
}

// ===== FALL DETECTION =====
void detectFall(ImuData data) {

  unsigned long now = millis();

  switch (state) {

    case NORMAL:
      if (data.accelMag < FREE_FALL_THRESH &&
          (now - lastFallTime > COOLDOWN_MS)) {

        state = FREE_FALL_DETECTED;
        freeFallTime = now;

        Serial.println("Free fall detected...");
      }
      break;

    case FREE_FALL_DETECTED:
      if (now - freeFallTime <= FALL_WINDOW_MS) {

        if (data.accelMag > IMPACT_THRESH &&
            data.gyroMag > GYRO_THRESH) {

          Serial.println("========== FALL DETECTED ==========");
          Serial.print("Impact Accel: ");
          Serial.print(data.accelMag);
          Serial.print(" g | Gyro: ");
          Serial.print(data.gyroMag);
          Serial.println(" deg/s");

          // ✅ SET GLOBAL FLAG HERE
          fallDetectedGlobal = true;

          lastFallTime = now;
          state = NORMAL;
        }

      } else {
        state = NORMAL;
      }
      break;
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);

  Serial.println("Initializing IMU on D6/D7...");

  I2C_2.begin(D6, D7, 400000);

  if (!imu.begin_I2C(0x6A, &I2C_2)) {
    if (!imu.begin_I2C(0x6B, &I2C_2)) {
      Serial.println("ERROR: IMU not found!");
      while (1);
    }
  }

  Serial.println("IMU initialized successfully!");
}

// ===== LOOP =====
void loop() {

  ImuData data = readIMU();

  Serial.print("Accel: ");
  Serial.print(data.accelMag);
  Serial.print(" g | Gyro: ");
  Serial.print(data.gyroMag);
  Serial.println(" deg/s");

  detectFall(data);

  // ===== OPTIONAL: PRINT FLAG =====
  if (fallDetectedGlobal) {
    Serial.println("fallDetectedGlobal = TRUE"); //To be sent via bluetooth
    fallDetectedGlobal = false; //Flag reset
  }

  delay(10);
}