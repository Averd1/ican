/*
 * Ambient Light Sensor Implementation
 * Typically uses TSL2559 or similar I2C light sensor
 */

#include "light.h"
#include <Wire.h>

#define LIGHT_SENSOR_ADDR 0x39  // TSL2561 I2C address (verify for your sensor)
#define LOW_LIGHT_THRESHOLD 100  // lux - threshold to enable LED

uint16_t ambientLux = 0;
bool lowLightDetected = false;

void lightSensorInit() {
    selectLidar();  // Route I2C to light sensor via mux

    // Initialize light sensor communication
    Wire.beginTransmission(LIGHT_SENSOR_ADDR);
    if (Wire.endTransmission() == 0) {
        if (DEBUG_MODE) Serial.println("Ambient light sensor initialized");
    } else {
        if (DEBUG_MODE) Serial.println("Ambient light sensor not found");
    }
}

void lightSensorUpdate() {
    selectLidar();  // Ensure correct I2C mux channel

    // Read light sensor data (varies by sensor model)
    // Example for TSL2561: 2-channel (infrared + visible light)

    Wire.beginTransmission(LIGHT_SENSOR_ADDR);
    Wire.write(0x8C);  // DATA0 register (visible light channel)
    if (Wire.endTransmission() != 0) {
        return;  // Error reading
    }

    Wire.requestFrom(LIGHT_SENSOR_ADDR, 2);
    if (Wire.available() >= 2) {
        uint8_t low = Wire.read();
        uint8_t high = Wire.read();
        uint16_t rawadc = (high << 8) | low;

        // Convert sensor ADC to lux (formula varies by sensor)
        // This is approximate - calibrate for your specific sensor
        ambientLux = (rawadc * 375) / 10000;  // Rough calibration

        // Update low light detection
        lowLightDetected = (ambientLux < LOW_LIGHT_THRESHOLD);

        if (DEBUG_MODE && millis() % 5000 < 100) {
            Serial.print("Ambient Light: ");
            Serial.print(ambientLux);
            Serial.print(" lux ");
            Serial.println(lowLightDetected ? "(LOW LIGHT - LED ON)" : "(NORMAL)");
        }
    }
}