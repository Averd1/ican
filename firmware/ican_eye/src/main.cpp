/**
 * ============================================================================
 * iCan Eye — Main Firmware Entry Point
 * Target: Seeed XIAO ESP32-S3 Sense
 * ============================================================================
 *
 * Initializes the camera and BLE subsystems, then waits for commands from a
 * connected BLE client (phone or computer).
 *
 * Subsystems (see lib/ for individual module implementations):
 *   - Camera: OV2640 via esp_camera, profile-based quality selection
 *   - BLE: NimBLE peripheral using shared iCan Eye service UUIDs
 *
 * ============================================================================
 */

#include <Arduino.h>

// Local library headers (implemented in lib/ subdirectories)
#include "ble_eye.h"
#include "camera.h"

// Shared protocol (included via -I../../shared build flag)
#include "ble_protocol.h"

// ============================================================================
// Setup
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== iCan Eye Firmware ===");

  // Initialize subsystems
  initCamera();
  initBleEye();

  Serial.printf("[Main] Default profile: %d (%s)\n", getCurrentProfile(),
                profiles[getCurrentProfile()].name);
  Serial.println("[Main] Ready — waiting for BLE connection...");
}

// ============================================================================
// Main Loop
// ============================================================================

void loop() {
  // Check for pending BLE commands
  EyeCommandData cmd = getLastEyeCommand();

  switch (cmd.type) {
  case EYE_CMD_CAPTURE: {
    if (!isBleEyeConnected()) {
      Serial.println("[Main] Capture requested but no client connected.");
      break;
    }
    camera_fb_t *fb = capturePhoto();
    if (fb) {
      streamImageViaBle(fb->buf, fb->len,
                        profiles[getCurrentProfile()].name);
      esp_camera_fb_return(fb);
    }
    break;
  }

  case EYE_CMD_PROFILE: {
    if (cmd.profileIndex >= 0 && cmd.profileIndex < NUM_PROFILES) {
      applyProfile(cmd.profileIndex);
      // Notify client of profile change
      char msg[64];
      snprintf(msg, sizeof(msg), "PROFILE_SET:%d:%s", cmd.profileIndex,
               profiles[cmd.profileIndex].name);
      sendControlMessage(msg);
    } else {
      Serial.printf("[Main] Invalid profile index: %d\n", cmd.profileIndex);
    }
    break;
  }

  case EYE_CMD_STATUS:
    Serial.printf("[Main] Current profile: %d (%s)\n", getCurrentProfile(),
                  profiles[getCurrentProfile()].name);
    break;

  case EYE_CMD_NONE:
  default:
    break;
  }

  delay(10);
}
