#include "mode.h"
#include <Arduino.h>

// Battery monitoring pins (adjust based on hardware)
#define BATTERY_PIN A0  // Analog pin for battery voltage divider
#define BATTERY_R1 10000.0  // Voltage divider resistor 1 (10k)
#define BATTERY_R2 3300.0   // Voltage divider resistor 2 (3.3k)
#define BATTERY_VREF 3.3    // ESP32 ADC reference voltage
#define BATTERY_MAX_V 4.2   // LiPo max voltage
#define BATTERY_MIN_V 3.0   // LiPo min voltage

Mode currentMode = NORMAL;
ModeConfig config;
int batteryLevel = 100; // Start with 100%

void setMode(Mode m) {
    currentMode = m;

    switch(m) {
        case NORMAL:
            // Normal operation: balanced performance and power
            config.imuInterval = 50;        // 20 Hz (LSM6DSOX max ~6.6kHz)
            config.ultrasonicInterval = 100; // 10 Hz (URM37 max ~50Hz)
            config.lidarInterval = 100;     // 10 Hz (TF Luna max ~1000Hz)
            config.pulseInterval = 200;     // 5 Hz (adequate for heart rate)
            config.batteryCheckInterval = 5000; // Check battery every 5 seconds
            break;

        case LOW_POWER:
            // Low power: reduce sampling to extend battery life
            config.imuInterval = 200;       // 5 Hz
            config.ultrasonicInterval = 500; // 2 Hz
            config.lidarInterval = 500;     // 2 Hz
            config.pulseInterval = 1000;    // 1 Hz (minimal heart rate monitoring)
            config.batteryCheckInterval = 10000; // Check battery every 10 seconds
            break;

        case EMERGENCY:
            // Emergency: maximum sampling for critical monitoring
            config.imuInterval = 10;        // 100 Hz (for fall detection)
            config.ultrasonicInterval = 50;  // 20 Hz
            config.lidarInterval = 50;      // 20 Hz
            config.pulseInterval = 20;      // 50 Hz (rapid heart rate monitoring)
            config.batteryCheckInterval = 1000; // Check battery every 1 second
            break;
    }
}

// Read battery level as percentage (0-100)
int getBatteryLevel() {
    // Read analog voltage
    int adcValue = analogRead(BATTERY_PIN);

    // Convert ADC to voltage
    float voltage = (adcValue / 4095.0) * BATTERY_VREF * ((BATTERY_R1 + BATTERY_R2) / BATTERY_R2);

    // Convert voltage to percentage
    if (voltage >= BATTERY_MAX_V) {
        batteryLevel = 100;
    } else if (voltage <= BATTERY_MIN_V) {
        batteryLevel = 0;
    } else {
        batteryLevel = (int)((voltage - BATTERY_MIN_V) / (BATTERY_MAX_V - BATTERY_MIN_V) * 100.0);
    }

    return batteryLevel;
}
