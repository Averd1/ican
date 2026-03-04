/**
 * haptics.cpp — DRV2605L Haptic Driver Implementation
 */

#include "haptics.h"
#include <Adafruit_DRV2605.h>

static Adafruit_DRV2605 drv;

void initHaptics() {
  if (!drv.begin()) {
    Serial.println("[Haptics] ERROR: DRV2605 not found!");
    return;
  }
  drv.selectLibrary(1); // Built-in ERM library
  drv.setMode(DRV2605_MODE_INTTRIG);
  Serial.println("[Haptics] DRV2605 initialized.");
}

void playPattern(HapticPattern pattern) {
  // Map our logical pattern to DRV2605L waveform effects.
  // See DRV2605L datasheet Table 11.2 for waveform IDs.
  uint8_t waveform = 0;

  switch (pattern) {
  case PATTERN_OBSTACLE_LEFT:
  case PATTERN_OBSTACLE_RIGHT:
    waveform = 17; // Strong Click — 100%
    break;
  case PATTERN_OBSTACLE_HEAD:
    waveform = 47; // Buzz 1 — 100% (sharp alert)
    break;
  case PATTERN_NAV_LEFT:
  case PATTERN_NAV_RIGHT:
    waveform = 14; // Soft Bump — 100% (gentle guide)
    break;
  case PATTERN_NAV_STRAIGHT:
    waveform = 10; // Double Click — 60%
    break;
  case PATTERN_ARRIVED:
    waveform = 16; // Alert 1000ms
    break;
  case PATTERN_FALL_ALERT:
    waveform = 49; // Buzz 3 — strong rapid triple
    break;
  default:
    return;
  }

  drv.setWaveform(0, waveform);
  drv.setWaveform(1, 0); // End sequence
  drv.go();
}

void stopHaptics() { drv.stop(); }
