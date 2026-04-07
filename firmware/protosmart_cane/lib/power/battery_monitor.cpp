/*
 * Battery Monitoring Implementation
 */

#include "battery_monitor.h"
#include <Arduino.h>

BatteryStatus batteryStatus = {100, 4.2f, 0, 0, 0, &PROFILE_NORMAL};

void batteryMonitorInit() {
    if (DEBUG_MODE) Serial.println("Battery monitor initialized");
}

void updateBatteryMonitor() {
    // Read battery voltage
    int adcValue = analogRead(BATTERY_PIN);
    batteryStatus.voltage = (adcValue / 4095.0f) * BATTERY_VREF * ((BATTERY_R1 + BATTERY_R2) / BATTERY_R2);

    // Convert voltage to percentage
    if (batteryStatus.voltage >= BATTERY_MAX_V) {
        batteryStatus.percentage = 100;
    } else if (batteryStatus.voltage <= BATTERY_MIN_V) {
        batteryStatus.percentage = 0;
    } else {
        batteryStatus.percentage = (int)((batteryStatus.voltage - BATTERY_MIN_V) / 
                                        (BATTERY_MAX_V - BATTERY_MIN_V) * 100.0f);
    }

    // Update warning levels
    if (batteryStatus.percentage < CRITICAL_BATTERY_THRESHOLD) {
        batteryStatus.warningLevel = 1;  // Critical
    } else if (batteryStatus.percentage < LOW_POWER_WARNING_THRESHOLD) {
        batteryStatus.warningLevel = 2;  // Low
    } else {
        batteryStatus.warningLevel = 0;  // OK
    }

    // Select power profile based on mode
    switch(currentMode) {
        case NORMAL:
            batteryStatus.currentProfile = &PROFILE_NORMAL;
            break;
        case LOW_POWER:
            batteryStatus.currentProfile = &PROFILE_LOW_POWER;
            break;
        case EMERGENCY:
            batteryStatus.currentProfile = &PROFILE_EMERGENCY;
            break;
    }

    if (batteryStatus.currentProfile) {
        batteryStatus.currentDraw = batteryStatus.currentProfile->totalActivePower;
    }

    // Update runtime estimate
    updateBatteryEstimate();
}

float estimateRuntimeMinutes(int batteryPercent, float powerDrawmA) {
    if (powerDrawmA <= 0) return 0;

    // Wh = (Voltage × Capacity_mAh) / 1000
    float energyWh = BATTERY_NOMINAL_VOLTAGE * (BATTERY_CAPACITY_MAH * BATTERY_USABLE_CAPACITY) / 1000.0f;

    // Available energy based on current battery %
    float availableEnergy = energyWh * (batteryPercent / 100.0f);

    // Runtime = Energy (Wh) / Power (W)
    float runtimeHours = availableEnergy / (powerDrawmA * BATTERY_NOMINAL_VOLTAGE / 1000.0f);

    return runtimeHours * 60.0f;  // Convert to minutes
}

void updateBatteryEstimate() {
    batteryStatus.estimatedRuntime = estimateRuntimeMinutes(batteryStatus.percentage, batteryStatus.currentDraw);

    if (DEBUG_MODE && millis() % 10000 < 100) {
        Serial.print("Battery: ");
        Serial.print(batteryStatus.percentage);
        Serial.print("% (");
        Serial.print(batteryStatus.voltage, 2);
        Serial.print("V) | Draw: ");
        Serial.print(batteryStatus.currentDraw, 1);
        Serial.print("mA | Runtime: ~");
        Serial.print((int)batteryStatus.estimatedRuntime);
        Serial.println(" min");
    }
}