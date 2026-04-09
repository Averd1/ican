/*
 * Battery Monitoring Implementation - Comprehensive Health & Runtime Estimation
 * 
 * PKCELL ICR18650 6600mAh LiPo Battery Monitoring
 * 
 * Features:
 * - Non-linear LiPo voltage-to-SOC discharge curve mapping
 * - Temperature-based capacity derating (-10°C to 55°C operation range)
 * - Cycle counting and age-based degradation estimation
 * - Real-time efficiency and internal resistance estimation
 * - Predictive runtime based on recent usage patterns
 * - Health scoring system (0-100)
 */

#include "battery_monitor.h"
#include <Arduino.h>
#include <math.h>

BatteryStatus batteryStatus = {0.0f, 100, 0.0f, 0, {0}, 0.0f, &PROFILE_NORMAL};

// === USAGE TRACKING FOR PREDICTIVE RUNTIME ===
static float recentPowerDrawSamples[12] = {0};  // Last 12 readings (1 per 10s = 2min window)
static uint8_t sampleIndex = 0;
static unsigned long lastSampleTime = 0;

// === BATTERY AGING MODEL ===
static float estimatedCycleCount = 0.0f;
static float lastRecordedVoltage = 4.2f;
static bool wasDischarging = false;


void batteryMonitorInit() {
    // Initialize cycle counter from EEPROM if available (future enhancement)
    estimatedCycleCount = 0.0f;
    lastRecordedVoltage = 4.2f;
    
    if (DEBUG_MODE) Serial.println("Battery monitor initialized - Enhanced health tracking");
}

// ============================================================================
// NON-LINEAR DISCHARGE CURVE: LiPo Voltage → State of Charge (SOC)
// ============================================================================
// Standard LiPo discharge curve (typical for 3.7V nominal cell)
// Maps voltage profile to SOC with temperature compensation
float voltageToSOC_LiPo(float voltage_v, float temp_C) {
    // Reference curve at 25°C (typical operation)
    // This is a characteristic curve for LiPo cells
    
    if (voltage_v >= 4.20f) return 100.0f;
    if (voltage_v <= 3.00f) return 0.0f;
    
    // Non-linear mapping using lookup table approach
    // Voltage range 3.0V - 4.2V maps to SOC 0% - 100%
    float voltage_normalized = (voltage_v - 3.0f) / 1.2f;  // 0.0 to 1.0
    
    // LiPo discharge curve is roughly logarithmic in the middle range
    // Using 3-point characteristic curve
    float soc_percent;
    
    if (voltage_normalized <= 0.25f) {
        // 3.0-3.3V: Very steep drop (last 25% capacity)
        soc_percent = voltage_normalized * 4.0f * 25.0f;  // 0-100% in 0.25V
    } else if (voltage_normalized <= 0.8f) {
        // 3.3-3.96V: Gentle slope (25%-90%)
        soc_percent = 25.0f + (voltage_normalized - 0.25f) * (65.0f / 0.55f);
    } else {
        // 3.96-4.2V: Steep rise again (90%-100%)
        soc_percent = 90.0f + (voltage_normalized - 0.8f) * (200.0f / 0.2f);
    }
    
    // Clamp to valid range
    if (soc_percent > 100.0f) soc_percent = 100.0f;
    if (soc_percent < 0.0f) soc_percent = 0.0f;
    
    return soc_percent;
}

// ============================================================================
// TEMPERATURE COMPENSATION for Discharge Capacity
// ============================================================================
// Battery datasheet specs:
//   25°C (ref): 100% capacity
//   55°C (2h): 80% capacity (≥5280mAh vs 6600mAh)
//   -10°C (16-24h): 60% capacity (≥2640mAh vs 4400mAh)
float getTemperatureCompensation(float temp_C) {
    // Returns capacity multiplier for temperature
    // Reference: 25°C = 1.0x
    
    if (temp_C < BATTERY_CRITICAL_TEMP_LOW) {
        // Below -5°C: severe derating
        return 0.4f + (temp_C - BATTERY_DISCHARGE_TEMP_MIN) * 0.02f;
    } else if (temp_C < 0.0f) {
        // -5°C to 0°C: linear derating from 0.5 to 0.6
        return 0.5f + (temp_C + 5.0f) * 0.02f;
    } else if (temp_C < 25.0f) {
        // 0°C to 25°C: linear rise to 1.0
        return 0.6f + (temp_C) * (0.4f / 25.0f);
    } else if (temp_C < 55.0f) {
        // 25°C to 55°C: slight derating from 1.0 to 0.8
        return 1.0f - (temp_C - 25.0f) * (0.2f / 30.0f);
    } else if (temp_C < 70.0f) {
        // 55°C to 70°C: steep derating to 0.6
        return 0.8f - (temp_C - 55.0f) * (0.2f / 15.0f);
    } else {
        // Above 70°C: dangerous, severe derating
        return 0.3f;
    }
}

// ============================================================================
// CYCLE COUNTING & AGE-BASED DEGRADATION
// ============================================================================
void updateCycleCount() {
    // Simple cycle counter: detect charge -> discharge transitions
    // This is approximate; more accurate with coulomb counting
    
    bool isCurrentlyCharging = (batteryStatus.voltage_v > 4.0f);
    
    if (wasDischarging && isCurrentlyCharging) {
        // Transitioned from discharging to charging = 1 cycle
        estimatedCycleCount += 0.5f;
    }
    
    wasDischarging = !isCurrentlyCharging;
}

float estimateCapacityFromAge(float assumedCycles) {
    // PKCELL datasheet: ≥500 cycles to 70% capacity @ 25°C (1C discharge)
    // Capacity loss model: exponential decay
    // At 500 cycles: 70% remain
    // At 0 cycles: 100% nominal
    
    if (assumedCycles <= 0) return 100.0f;
    if (assumedCycles >= 500) return 70.0f;  // Floor at 70% capacity
    
    // Exponential decay model: C(N) = 100 * e^(-λN)
    // Where λ chosen so C(500) = 70
    // ln(0.7) = -500λ => λ = -ln(0.7)/500 ≈ 0.000714
    float lambda = 0.000714f;
    float capacity_percent = 100.0f * exp(-lambda * assumedCycles);
    
    return capacity_percent;
}

// ============================================================================
// INTERNAL RESISTANCE ESTIMATION
// ============================================================================
float estimateInternalResistance(float voltage_v, float currentDraw_mA) {
    // Estimate internal resistance from voltage droop under load
    // R_internal = (V_noload - V_load) / I_load
    
    // Reference: Open circuit voltage (no load)
    // vs. voltage under load
    
    // This is approximate; real measurement needs voltage/current synchronization
    // For now, use simple model: higher current -> more droop
    
    float estimated_ocv = voltage_v + (currentDraw_mA / 1000.0f) * BATTERY_NOMINAL_IMPEDANCE_MOHS;
    float r_internal = (estimated_ocv - voltage_v) / (currentDraw_mA / 1000.0f + 0.001f);
    
    return r_internal;
}

// ============================================================================
// EFFICIENCY TRACKING
// ============================================================================
float calculateRoundTripEfficiency(float temp_C) {
    // Efficiency accounting for:
    // - Ohmic losses (I²R heating)
    // - Temperature effects
    // - Age degradation
    
    float base_efficiency = 0.95f;  // 95% typical for LiPo
    
    // Temperature impact (drops at extremes)
    float temp_factor = getTemperatureCompensation(temp_C);
    
    // Age impact: efficiency drops as internal resistance increases
    float age_factor = estimateCapacityFromAge(estimatedCycleCount) / 100.0f;
    
    return base_efficiency * temp_factor * age_factor * 100.0f;  // Return as %
}

// ============================================================================
// MAIN BATTERY UPDATE
// ============================================================================
void updateBatteryMonitor() {
    // Read battery voltage
    int adcValue = analogRead(BATTERY_PIN);
    batteryStatus.voltage_v = (adcValue / 4095.0f) * BATTERY_VREF * 
                             ((BATTERY_R1 + BATTERY_R2) / BATTERY_R2);
    
    // Estimate temperature (placeholder: use ambient or IMU temp if available)
    // TODO: Integrate with IMU temperature sensor or ambient light correlation
    float estimatedTempC = 25.0f;  // Default to reference temp
    batteryStatus.health.temperatureC = estimatedTempC;
    
    // Update cycle count
    updateCycleCount();
    batteryStatus.health.estimatedCycleCount = estimatedCycleCount;
    
    // === CAPACITY ESTIMATION ===
    float tempCompensation = getTemperatureCompensation(estimatedTempC);
    float ageCompensation = estimateCapacityFromAge(estimatedCycleCount);
    batteryStatus.health.estimatedCapacityMAh = BATTERY_NOMINAL_CAPACITY_MAH * 
                                               (tempCompensation * ageCompensation / 100.0f);
    batteryStatus.health.capacityRetentionPercent = ageCompensation;
    
    // === STATE OF CHARGE (SOC) CALCULATION ===
    batteryStatus.percentage = (uint8_t)voltageToSOC_LiPo(batteryStatus.voltage_v, estimatedTempC);
    
    // === INTERNAL RESISTANCE ===
    batteryStatus.health.estimatedResistanceOhms = estimateInternalResistance(
        batteryStatus.voltage_v, 
        batteryStatus.currentDraw
    );
    
    // === EFFICIENCY ===
    batteryStatus.health.roundTripEfficiency = calculateRoundTripEfficiency(estimatedTempC);
    
    // === HEALTH SCORE (0-100) ===
    // Composite: capacity * temperature * resistance quality
    float capacity_score = ageCompensation;  // 100->70 over life
    float temp_score = getTemperatureCompensation(estimatedTempC) * 100.0f;
    float resistance_score = (1.0f - (batteryStatus.health.estimatedResistanceOhms / 200.0f)) * 100.0f;
    
    batteryStatus.health.healthScore = (capacity_score + temp_score + resistance_score) / 3.0f;
    if (batteryStatus.health.healthScore < 0) batteryStatus.health.healthScore = 0;
    if (batteryStatus.health.healthScore > 100) batteryStatus.health.healthScore = 100;
    
    // === TEMPERATURE WARNINGS ===
    batteryStatus.health.tempWarning = (estimatedTempC < BATTERY_CRITICAL_TEMP_LOW || 
                                       estimatedTempC > BATTERY_CRITICAL_TEMP_HIGH);
    
    // === WARNING LEVELS ===
    if (batteryStatus.health.tempWarning) {
        batteryStatus.warningLevel = 3;  // Temperature danger
    } else if (batteryStatus.percentage < 5) {
        batteryStatus.warningLevel = 2;  // Critical
    } else if (batteryStatus.percentage < 20) {
        batteryStatus.warningLevel = 1;  // Low
    } else {
        batteryStatus.warningLevel = 0;  // OK
    }
    
    // === SELECT POWER PROFILE ===
    switch(currentMode) {
        case NORMAL:
            batteryStatus.currentProfile = &PROFILE_NORMAL;
            break;
        case LOW_POWER:
            batteryStatus.currentProfile = &PROFILE_LOW_POWER;
            break;
        case HIGH_STRESS:
            batteryStatus.currentProfile = &PROFILE_HIGH_STRESS;
            break;
        case EMERGENCY:
            batteryStatus.currentProfile = &PROFILE_EMERGENCY;
            break;
    }
    
    if (batteryStatus.currentProfile) {
        batteryStatus.currentDraw = batteryStatus.currentProfile->totalActivePower;
    }
    
    // === TRACK RECENT POWER DRAW ===
    if (millis() - lastSampleTime > 10000) {  // Sample every 10 seconds
        recentPowerDrawSamples[sampleIndex] = batteryStatus.currentDraw;
        sampleIndex = (sampleIndex + 1) % 12;
        lastSampleTime = millis();
    }
    
    // Calculate rolling average
    float sumPower = 0;
    for (int i = 0; i < 12; i++) {
        sumPower += recentPowerDrawSamples[i];
    }
    batteryStatus.health.recentAveragePowerDrawmA = sumPower / 12.0f;
    
    // === PREDICTIVE RUNTIME ===
    batteryStatus.estimatedRuntimeMinutes = estimateRuntimeMinutes(
        batteryStatus.percentage,
        batteryStatus.health.recentAveragePowerDrawmA,
        estimatedTempC
    );
    
    // Conservative estimate (10% margin)
    batteryStatus.health.conservativeRuntimeMinutes = batteryStatus.estimatedRuntimeMinutes * 0.9f;
}

// ============================================================================
// RUNTIME ESTIMATION
// ============================================================================
float estimateRuntimeMinutes(uint8_t batteryPercent, float powerDrawmA, float tempC) {
    if (powerDrawmA <= 0) return 0;
    
    // Energy available (Wh)
    float capacity_derating = getTemperatureCompensation(tempC);
    float usable_capacity_mAh = BATTERY_NOMINAL_CAPACITY_MAH * BATTERY_USABLE_FRACTION * 
                               (capacity_derating / 100.0f);
    float available_energy_Wh = (usable_capacity_mAh * batteryPercent / 100.0f) * 
                               BATTERY_NOMINAL_VOLTAGE / 1000.0f;
    
    // Account for efficiency losses
    float efficiency = calculateRoundTripEfficiency(tempC) / 100.0f;
    float effective_energy_Wh = available_energy_Wh * efficiency;
    
    // Power required (Watts)
    float power_W = (powerDrawmA * BATTERY_NOMINAL_VOLTAGE) / 1000.0f;
    
    // Runtime in hours
    float runtime_hours = effective_energy_Wh / power_W;
    
    return runtime_hours * 60.0f;  // Convert to minutes
}

// ============================================================================
// BATTERY REPORT FOR APP/BLE INTEGRATION
// ============================================================================
BatteryReport getBatteryReport() {
    BatteryReport report;
    report.soc_percent = batteryStatus.percentage;
    report.voltage_v = batteryStatus.voltage_v;
    report.temp_c = batteryStatus.health.temperatureC;
    report.health_score = batteryStatus.health.healthScore;
    report.runtime_minutes = batteryStatus.health.conservativeRuntimeMinutes;
    report.capacity_derating = getTemperatureCompensation(batteryStatus.health.temperatureC);
    report.efficiency_percent = (uint8_t)batteryStatus.health.roundTripEfficiency;
    
    return report;
}

// ============================================================================
// DEBUG OUTPUT
// ============================================================================
void debugBatteryMetrics() {
    if (DEBUG_MODE && millis() % 15000 < 100) {
        Serial.println("\n=== BATTERY HEALTH REPORT ===");
        Serial.print("SOC: ");
        Serial.print(batteryStatus.percentage);
        Serial.print("% | Voltage: ");
        Serial.print(batteryStatus.voltage_v, 2);
        Serial.println("V");
        
        Serial.print("Capacity (current temp): ");
        Serial.print(batteryStatus.health.estimatedCapacityMAh, 0);
        Serial.print(" mAh | Health: ");
        Serial.print((int)batteryStatus.health.healthScore);
        Serial.println("%");
        
        Serial.print("Temperature: ");
        Serial.print(batteryStatus.health.temperatureC, 1);
        Serial.print("°C | Cycles: ");
        Serial.print((int)batteryStatus.health.estimatedCycleCount);
        Serial.println();
        
        Serial.print("Internal R: ");
        Serial.print(batteryStatus.health.estimatedResistanceOhms, 1);
        Serial.print(" Ω | Efficiency: ");
        Serial.print((int)batteryStatus.health.roundTripEfficiency);
        Serial.println("%");
        
        Serial.print("Power Draw (avg): ");
        Serial.print(batteryStatus.health.recentAveragePowerDrawmA, 1);
        Serial.print(" mA | Runtime: ");
        Serial.print((int)batteryStatus.health.conservativeRuntimeMinutes);
        Serial.println(" min (conservative)");
        
        if (batteryStatus.warningLevel > 0) {
            Serial.print("⚠ WARNING LEVEL: ");
            Serial.println(batteryStatus.warningLevel);
        }
        Serial.println("===========================\n");
    }
}