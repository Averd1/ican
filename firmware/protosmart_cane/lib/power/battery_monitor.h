/*
 * Battery Monitoring and Health Estimation
 * 
 * Provides comprehensive battery health metrics, runtime estimation,
 * and efficiency calculations without relying on app-side computations.
 * 
 * Features:
 * - Non-linear LiPo discharge curve mapping (voltage → SoC)
 * - Temperature compensation (datasheet rated -10°C to 55°C)
 * - Age/cycle estimation and capacity degradation modeling
 * - Real-time efficiency tracking and internal resistance estimation
 * - Predictive runtime based on recent usage patterns
 * - Health scoring system (0-100)
 */

#pragma once

#include "../include/power_profile.h"

// PKCELL ICR18650 4400mAh Battery Specs from Datasheet
#define BATTERY_NOMINAL_CAPACITY_MAH 4400.0f      // Typical capacity
#define BATTERY_MIN_CAPACITY_MAH 4180.0f          // Minimum rated
#define BATTERY_NOMINAL_VOLTAGE 3.7f              // Nominal voltage (V)
#define BATTERY_MAX_VOLTAGE 4.2f                  // Charging cutoff (V)
#define BATTERY_MIN_SAFE_VOLTAGE 3.0f             // Discharge cutoff (V)
#define BATTERY_USABLE_FRACTION 0.9f              // Usable capacity (90%)
#define BATTERY_RATED_CYCLE_LIFE 500              // Cycles @ 25°C to 70% capacity

// Temperature Range Specifications (from datasheet Section 9)
#define BATTERY_CHARGE_TEMP_MIN 0.0f              // °C
#define BATTERY_CHARGE_TEMP_MAX 45.0f             // °C
#define BATTERY_DISCHARGE_TEMP_MIN -20.0f         // °C
#define BATTERY_DISCHARGE_TEMP_MAX 70.0f          // °C
#define BATTERY_OPTIMAL_TEMP 25.0f                // Reference temperature

// Health Thresholds
#define BATTERY_CAPACITY_RECALIBRATION_CYCLES 50  // Recalibrate every N cycles
#define BATTERY_HEALTH_EXCELLENT 90               // % of nominal capacity
#define BATTERY_HEALTH_GOOD 80                    // %
#define BATTERY_HEALTH_FAIR 70                    // %
#define BATTERY_CRITICAL_TEMP_LOW -5.0f           // Warn if below (°C)
#define BATTERY_CRITICAL_TEMP_HIGH 50.0f          // Warn if above (°C)

// Internal Resistance Thresholds (estimated @ 1kHz AC)
#define BATTERY_NOMINAL_IMPEDANCE_MOHS 50         // mΩ (from datasheet)
#define BATTERY_HIGH_IMPEDANCE_WARNING 150        // mΩ (degrades with age)

struct BatteryHealth {
    // Capacity and Aging
    float estimatedCapacityMAh;       // Current capacity accounting for temp + age
    float capacityRetentionPercent;   // % of original capacity remaining
    float estimatedCycleCount;        // Estimated charge/discharge cycles
    float healthScore;                // 0-100 (100=perfect, 0=dead)
    
    // Thermal Status
    float temperatureC;               // Battery temperature (estimated from IMU or ambient)
    bool tempWarning;                 // True if outside optimal range
    
    // Internal Resistance (estimated under load)
    float estimatedResistanceOhms;    // Internal impedance estimate
    float voltageDropUnderLoadV;      // Voltage sag during peak current
    
    // Efficiency Metrics
    float roundTripEfficiency;        // % (estimates charging + discharging losses)
    float currentEfficiencyPercent;   // Real-time efficiency vs. theoretical
    
    // Predictive Runtime
    float recentAveragePowerDrawmA;   // 5-minute rolling average
    float predictedRuntimeMinutes;    // Based on recent usage pattern
    float conservativeRuntimeMinutes; // 10% margin buffer for uncertainty
};

struct BatteryStatus {
    // Voltage & Capacity
    float voltage_v;                  // Current measured voltage
    uint8_t percentage;               // SOC-based percentage (0-100)
    float estimatedRuntimeMinutes;    // Remaining runtime in minutes
    
    // Health & Warnings
    uint8_t warningLevel;             // 0=normal, 1=low, 2=critical, 3=temperature danger
    BatteryHealth health;             // Detailed health metrics
    
    // Current Draw & Profile
    float currentDraw;                // Current consumption (mA)
    const PowerProfile* currentProfile;
};

extern BatteryStatus batteryStatus;

// Core Functions
void batteryMonitorInit();
void updateBatteryMonitor();

// Health Estimation (internal use)
float estimateRuntimeMinutes(uint8_t batteryPercent, float powerDrawmA, float tempC);
float voltageToSOC_LiPo(float voltage_v, float temp_C);    // Non-linear curve
float getTemperatureCompensation(float temp_C);
float estimateCapacityFromAge(float assumedCycles);
float estimateInternalResistance(float voltage_v, float currentDraw_mA);

// For app integration
struct BatteryReport {
    uint8_t soc_percent;
    float voltage_v;
    float temp_c;
    float health_score;
    float runtime_minutes;
    float capacity_derating;
    uint8_t efficiency_percent;
};

BatteryReport getBatteryReport();  // Summary for BLE telemetry
void debugBatteryMetrics();         // Serial printout of all health data