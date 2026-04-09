/*
 * 8x8 Matrix Sensor Header
 *
 * Features:
 * - Hysteresis thresholds for zone transitions
 * - Distance smoothing with exponential moving average
 * - Zone persistence (N-frame confirmation)
 * - Fast approach velocity detection
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"

void matrixSensorInit();
void matrixSensorUpdate();

// Accessor functions for advanced response logic
uint16_t matrixSensorGetSmoothedDistance();  // Get EMA-smoothed distance for logging/debug
bool matrixSensorIsFastApproach();           // Check if object is approaching rapidly (>threshold)