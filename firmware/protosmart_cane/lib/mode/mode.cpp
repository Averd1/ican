/*
 * Power Mode Management
 * Controls sampling rates and system behavior based on power mode
 */

#include "mode.h"
#include "../include/state.h"

void setMode(SystemMode newMode) {
    currentMode = newMode;

    switch(newMode) {
        case NORMAL:
            // Balanced performance and power consumption
            modeConfig.imuInterval = NORMAL_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = NORMAL_ULTRASONIC_INTERVAL;
            modeConfig.lidarInterval = NORMAL_LIDAR_INTERVAL;
            modeConfig.pulseInterval = NORMAL_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = NORMAL_BATTERY_CHECK_INTERVAL;
            break;

        case LOW_POWER:
            // Reduced sampling to extend battery life
            modeConfig.imuInterval = LOW_POWER_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = LOW_POWER_ULTRASONIC_INTERVAL;
            modeConfig.lidarInterval = LOW_POWER_LIDAR_INTERVAL;
            modeConfig.pulseInterval = LOW_POWER_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = LOW_POWER_BATTERY_CHECK_INTERVAL;
            break;

        case EMERGENCY:
            // Maximum sampling for critical monitoring (with timeout protection)
            modeConfig.imuInterval = EMERGENCY_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = EMERGENCY_ULTRASONIC_INTERVAL;
            modeConfig.lidarInterval = EMERGENCY_LIDAR_INTERVAL;
            modeConfig.pulseInterval = EMERGENCY_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = EMERGENCY_BATTERY_CHECK_INTERVAL;
            break;
    }
}

int getBatteryLevel() {
    // Read analog voltage from battery divider
    int adcValue = analogRead(BATTERY_PIN);

    // Convert ADC to voltage
    float voltage = (adcValue / 4095.0f) * BATTERY_VREF * ((BATTERY_R1 + BATTERY_R2) / BATTERY_R2);

    // Convert voltage to percentage with bounds checking
    if (voltage >= BATTERY_MAX_V) {
        return 100;
    } else if (voltage <= BATTERY_MIN_V) {
        return 0;
    } else {
        return (int)((voltage - BATTERY_MIN_V) / (BATTERY_MAX_V - BATTERY_MIN_V) * 100.0f);
    }
}