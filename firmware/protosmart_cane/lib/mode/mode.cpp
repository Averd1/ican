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
            // Responsive active navigation: 20Hz IMU, 15Hz ultrasonic, 20Hz 8x8 sensor, 10Hz pulse
            modeConfig.imuInterval = NORMAL_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = NORMAL_ULTRASONIC_INTERVAL;
            modeConfig.matrixSensorInterval = NORMAL_MATRIX_SENSOR_INTERVAL;
            modeConfig.pulseInterval = NORMAL_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = NORMAL_BATTERY_CHECK_INTERVAL;
            break;

        case LOW_POWER:
            // Battery fallback (<20%): 5Hz all sensors, no LED, minimal feedback
            modeConfig.imuInterval = LOW_POWER_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = LOW_POWER_ULTRASONIC_INTERVAL;
            modeConfig.matrixSensorInterval = LOW_POWER_MATRIX_SENSOR_INTERVAL;
            modeConfig.pulseInterval = LOW_POWER_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = LOW_POWER_BATTERY_CHECK_INTERVAL;
            break;

        case HIGH_STRESS:
            // Peak threat response: 50Hz IMU, 30Hz ultrasonic/8x8 sensor, 20Hz pulse, max haptics
            modeConfig.imuInterval = HIGH_STRESS_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = HIGH_STRESS_ULTRASONIC_INTERVAL;
            modeConfig.matrixSensorInterval = HIGH_STRESS_MATRIX_SENSOR_INTERVAL;
            modeConfig.pulseInterval = HIGH_STRESS_PULSE_INTERVAL;
            modeConfig.batteryCheckInterval = HIGH_STRESS_BATTERY_CHECK_INTERVAL;
            break;

        case EMERGENCY:
            // Fall/critical alert (<60s): 100Hz IMU, 40Hz sensors, max BLE, NO haptic
            modeConfig.imuInterval = EMERGENCY_IMU_INTERVAL;
            modeConfig.ultrasonicInterval = EMERGENCY_ULTRASONIC_INTERVAL;
            modeConfig.matrixSensorInterval = EMERGENCY_MATRIX_SENSOR_INTERVAL;
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