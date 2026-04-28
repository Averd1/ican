/**
 * camera.h — Camera Module Interface
 *
 * Wraps the XIAO ESP32-S3 Sense camera behind a clean
 * init / capture / profile API.  Callers never touch esp_camera directly.
 */

#ifndef CAMERA_H
#define CAMERA_H

#include "esp_camera.h"
#include <stdint.h>

// =========================================================================
// Quality Profiles
// =========================================================================

struct CameraProfile {
  const char *name;
  framesize_t frameSize;
  int jpegQuality; // 0-63, lower = better quality, bigger file
};

/** Number of available profiles. */
extern const int NUM_PROFILES;

/** Profile table — indexed by profile number. */
extern const CameraProfile profiles[];

// =========================================================================
// Public API
// =========================================================================

/**
 * Initialize the camera hardware and apply the default profile (BALANCED).
 * Must be called once in setup().
 */
void initCamera();

/**
 * Switch to a different quality profile on the fly.
 * @param idx  Profile index (0 = FAST … 3 = MAX).
 */
void applyProfile(int idx);

/**
 * Get the currently active profile index.
 */
int getCurrentProfile();

/**
 * Capture a fresh JPEG frame.  Discards a stale frame internally.
 * Caller MUST call esp_camera_fb_return(fb) when done.
 * Returns nullptr on failure.
 */
camera_fb_t *capturePhoto();

#endif // CAMERA_H
