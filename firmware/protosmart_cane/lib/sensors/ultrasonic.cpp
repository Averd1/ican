/*
 * Ultrasonic Sensor (URM37) Implementation
 * Handles distance measurement for obstacle detection
 */

#include "ultrasonic.h"
#include <Wire.h>

void ultrasonicInit() {
    selectUltrasonic();

    // Test communication
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    if (Wire.endTransmission() != 0) {
        if (DEBUG_MODE) Serial.println("Ultrasonic sensor initialization failed!");
        systemFaults.ultrasonic_fail = true;
        return;
    }

    if (DEBUG_MODE) Serial.println("Ultrasonic sensor initialized successfully");
    systemFaults.ultrasonic_fail = false;
}

void ultrasonicUpdate() {
    selectUltrasonic();

    ultrasonicNear = false;
    ultrasonicImminent = false;

    // Read all ultrasonic sensors
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        currentSensors.ultrasonicDistances[i] = readUltrasonicDistance(i);

        // Update zone detection flags
        if (currentSensors.ultrasonicDistances[i] != SENSOR_ERROR_DISTANCE) {
            if (currentSensors.ultrasonicDistances[i] <= OBSTACLE_IMMINENT_MM) {
                ultrasonicImminent = true;
                ultrasonicNear = true;
            } else if (currentSensors.ultrasonicDistances[i] <= OBSTACLE_NEAR_MM) {
                ultrasonicNear = true;
            }
        }
    }

    // Mark sensor as working if at least one reading is valid
    systemFaults.ultrasonic_fail = true;  // Assume failure
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        if (currentSensors.ultrasonicDistances[i] != SENSOR_ERROR_DISTANCE) {
            systemFaults.ultrasonic_fail = false;
            break;
        }
    }
}

uint16_t readUltrasonicDistance(uint8_t sensorIndex) {
    if (sensorIndex >= NUM_ULTRASONIC_SENSORS) return SENSOR_ERROR_DISTANCE;

    // Trigger measurement
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    Wire.write(0x04);  // Trigger register
    Wire.write(0x01);  // Start measurement
    if (Wire.endTransmission() != 0) {
        return SENSOR_ERROR_DISTANCE;
    }

    // Wait for measurement to complete (URM37 needs ~50ms)
    delay(50);

    // Read distance registers
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    Wire.write(0x01);  // Distance low byte register
    if (Wire.endTransmission() != 0) {
        return SENSOR_ERROR_DISTANCE;
    }

    Wire.requestFrom(ULTRASONIC_I2C_ADDR, 2);
    if (Wire.available() >= 2) {
        uint8_t low = Wire.read();
        uint8_t high = Wire.read();
        uint16_t distance = (high << 8) | low;

        // Validate reading (URM37 returns 0 for invalid readings)
        if (distance == 0 || distance > ULTRASONIC_MAX_RANGE_MM) {
            return SENSOR_ERROR_DISTANCE;
        }

        return distance;
    }

    return SENSOR_ERROR_DISTANCE;
}