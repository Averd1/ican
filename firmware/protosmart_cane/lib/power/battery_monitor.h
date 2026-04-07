/*
 * Battery Monitoring and Lifetime Estimation
 * Tracks power consumption and calculates remaining runtime
 */

#pragma once

#include "../include/power_profile.h"

struct BatteryStatus {
    int percentage;           // Current battery level (0-100%)
    float voltage;            // Current voltage
    float currentDraw;        // Estimated current draw (mA)
    float estimatedRuntime;   // Estimated runtime in minutes
    int warningLevel;         // 1 = critical (<5%), 2 = low (<15%), 0 = OK
    const PowerProfile* currentProfile;
};

extern BatteryStatus batteryStatus;

void batteryMonitorInit();
void updateBatteryMonitor();
float estimateRuntimeMinutes(int batteryPercent, float powerDrawmA);
void updateBatteryEstimate();