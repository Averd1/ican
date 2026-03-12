// ALL pins for references
// VDD  - I/O voltage level
// SDA - i2C data
//SCL - I2C dock 
//CS Select comm (SPI/I2C)
//SDO/SA0 - I2C address select
//INT1 & 2 - Interrupt pins 

#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include <Adafruit_Sensor.h>

Adafruit_LSM6DSOX imu;

// interrupt + indicator
const int IMU_INTERRUPT_PIN = 32;
const int ALERT_LED = 25;

// thresholds
const float FREEFALL_THRESHOLD = 2.5;
const float STEP_ACCEL_THRESHOLD = 11.5;
const float TAP_THRESHOLD = 15.0;

volatile bool fallDetected = false;

unsigned long startTime;

void IRAM_ATTR imuInterruptHandler() {
    fallDetected = true;
}

void setup() {
    startTime = millis();
    Serial.begin(115200);
    delay(1000);

    pinMode(ALERT_LED, OUTPUT);
    pinMode(IMU_INTERRUPT_PIN, INPUT);

    attachInterrupt(digitalPinToInterrupt(IMU_INTERRUPT_PIN), imuInterruptHandler, RISING);

    Wire.begin();

    if (!imu.begin_I2C()) {
        Serial.println("IMU not detected");
        while(1);
    }
  

    imu.setAccelRange(LSM6DS_ACCEL_RANGE_4_G);
    imu.setGyroRange(LSM6DS_GYRO_RANGE_250_DPS);

    imu.setAccelDataRate(LSM6DS_RATE_104_HZ);
    imu.setGyroDataRate(LSM6DS_RATE_104_HZ);

    Serial.println("IMU initialized");
}

void loop() {
  if (millis() - startTime > 10000){
    whle(true);
  }
    testRawIMU();
   // testTiltDetection();
   // testStepCounter();
   // testTapDetection();
   // testFreeFallDetection();

    delay(200);
}

void testRawIMU() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    Serial.print("Accel: ");
    Serial.print(accel.acceleration.x); Serial.print(" ");
    Serial.print(accel.acceleration.y); Serial.print(" ");
    Serial.println(accel.acceleration.z);

    Serial.print("Gyro: ");
    Serial.print(gyro.gyro.x); Serial.print(" ");
    Serial.print(gyro.gyro.y); Serial.print(" ");
    Serial.println(gyro.gyro.z);
}

void testTiltDetection() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    if (abs(accel.acceleration.x) > 7) {
        Serial.println("Tilt left/right detected");
    }

    if (abs(accel.acceleration.y) > 7) {
        Serial.println("Tilt forward/back detected");
    }
}

void testTapDetection() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    float magnitude = sqrt(
        accel.acceleration.x * accel.acceleration.x +
        accel.acceleration.y * accel.acceleration.y +
        accel.acceleration.z * accel.acceleration.z
    );

    if (magnitude > TAP_THRESHOLD) {
        Serial.println("Tap detected");
    }
}

void testTapDetection() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    float magnitude = sqrt(
        accel.acceleration.x * accel.acceleration.x +
        accel.acceleration.y * accel.acceleration.y +
        accel.acceleration.z * accel.acceleration.z
    );

    if (magnitude > TAP_THRESHOLD) {
        Serial.println("Tap detected");
    }
}

void testFreeFallDetection() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    float magnitude = sqrt(
        accel.acceleration.x * accel.acceleration.x +
        accel.acceleration.y * accel.acceleration.y +
        accel.acceleration.z * accel.acceleration.z
    );

    if (magnitude < FREEFALL_THRESHOLD) {

        Serial.println("FREE FALL DETECTED");

        digitalWrite(ALERT_LED, HIGH);

        delay(2000);

        digitalWrite(ALERT_LED, LOW);
    }
}

void testInterruptFallLogic() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    float magnitude = sqrt(
        accel.acceleration.x * accel.acceleration.x +
        accel.acceleration.y * accel.acceleration.y +
        accel.acceleration.z * accel.acceleration.z
    );

    if (magnitude < FREEFALL_THRESHOLD) {

        Serial.println("FALL EVENT");

        Serial.print("Last accel reading: ");
        Serial.println(accel.acceleration.z);

        digitalWrite(ALERT_LED, HIGH);

        while(1) {
            // stop system until reset
        }
    }
}

void testFreeFallDetection() {

    sensors_event_t accel, gyro, temp;
    imu.getEvent(&accel, &gyro, &temp);

    float magnitude = sqrt(
        accel.acceleration.x * accel.acceleration.x +
        accel.acceleration.y * accel.acceleration.y +
        accel.acceleration.z * accel.acceleration.z
    );

    if (magnitude < FREEFALL_THRESHOLD) {

        Serial.println("FREE FALL DETECTED");

        digitalWrite(ALERT_LED, HIGH);

        delay(2000);

        digitalWrite(ALERT_LED, LOW);
    }
