/**
 * haptics.h — DRV2605L Haptic Driver Wrapper
 *
 * Provides pattern-based vibration control for the three motors
 * in the cane handle (left, right, top) via the I²C haptic driver.
 */

#ifndef HAPTICS_H
#define HAPTICS_H

#include "../../../shared/ble_protocol.h" // HapticPattern enum
#include <stdint.h>

/**
 * Initialize the DRV2605L haptic driver.
 * Must be called after selecting the correct I²C mux channel.
 */
void initHaptics();

/**
 * Trigger a haptic vibration pattern.
 *
 * @param pattern  One of the HapticPattern enum values from ble_protocol.h.
 *                 The DRV2605L waveform library is used internally.
 */
void playPattern(HapticPattern pattern);

/**
 * Stop any currently playing haptic pattern immediately.
 */
void stopHaptics();

#endif // HAPTICS_H
