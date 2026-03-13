/**
 * ============================================================================
 * iCan Eye — Camera Test Entry Point
 * Target: Seeed XIAO ESP32-S3 Sense
 * ============================================================================
 *
 * This is a standalone test application to verify the camera module
 * functionality without running the BLE server.
 * It initializes the camera and captures frames periodically, printing
 * stats to the Serial monitor.
 */

#include <Arduino.h>
#include "camera.h"

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  Serial.println("\n\n===================================");
  Serial.println("iCan Eye - Camera Test Application");
  Serial.println("===================================");
  
  // Initialize the camera module
  initCamera();
  
  Serial.println("Initialization complete. Starting capture loop...");
  Serial.println("===================================\n");
}

void loop() {
  // Capture a photo every 5 seconds
  static uint32_t lastCaptureTime = 0;
  uint32_t now = millis();
  
  if (now - lastCaptureTime >= 5000) {
    lastCaptureTime = now;
    
    Serial.println("\n--- CAPTURING PHOTO ---");
    camera_fb_t* fb = capturePhoto();
    
    if (fb) {
      Serial.printf("Success! Frame size: %u bytes\n", fb->len);
      Serial.printf("Format: JPEG\n");
      Serial.printf("Dimensions: %ux%u\n", fb->width, fb->height);
      
      // Free the framebuffer
      esp_camera_fb_return(fb);
    } else {
      Serial.println("ERROR: Failed to capture frame.");
    }
    Serial.println("------------------------");
  }
}
