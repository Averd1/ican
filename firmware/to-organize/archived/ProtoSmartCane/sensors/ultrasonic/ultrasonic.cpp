#include "ultrasonic.h"
#include "../../mux/mux.h"
#include <Wire.h>

bool ultrasonicNear = false;
bool ultrasonicImminent = false;
uint16_t ultrasonicDistances[NUM_ULTRASONIC] = {0, 0};

void initUltrasonic() {
    selectUltrasonic();

    // Test communication with URM37
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    if (Wire.endTransmission() == 0) {
        Serial.println("URM37 Ultrasonic initialized");
    } else {
        Serial.println("URM37 Ultrasonic initialization failed");
    }
}

void updateUltrasonicData() {
    selectUltrasonic();

    ultrasonicNear = false;
    ultrasonicImminent = false;

    // Read both ultrasonic sensors
    for (uint8_t i = 0; i < NUM_ULTRASONIC; i++) {
        ultrasonicDistances[i] = readUltrasonicDistance(i);

        // Update zone detection
        if (ultrasonicDistances[i] > 0 && ultrasonicDistances[i] <= ULTRASONIC_IMMINENT) {
            ultrasonicImminent = true;
            ultrasonicNear = true;
        } else if (ultrasonicDistances[i] > 0 && ultrasonicDistances[i] <= ULTRASONIC_NEAR) {
            ultrasonicNear = true;
        }
    }
}

uint16_t readUltrasonicDistance(uint8_t sensorIndex) {
    // For multiple sensors, we might need different addresses or additional mux channels
    // For now, assuming single URM37 sensor
    if (sensorIndex >= NUM_ULTRASONIC) return 0;

    // Trigger measurement
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    Wire.write(ULTRASONIC_TRIGGER);
    Wire.write(0x01); // Trigger measurement
    if (Wire.endTransmission() != 0) {
        return 0; // Error
    }

    delay(50); // URM37 measurement time ~50ms

    // Read distance registers
    Wire.beginTransmission(ULTRASONIC_I2C_ADDR);
    Wire.write(ULTRASONIC_DIST_LOW);
    if (Wire.endTransmission() != 0) {
        return 0; // Error
    }

    Wire.requestFrom(ULTRASONIC_I2C_ADDR, 2);
    if (Wire.available() >= 2) {
        uint8_t low = Wire.read();
        uint8_t high = Wire.read();
        return (high << 8) | low;
    }

    return 0; // No data available
}