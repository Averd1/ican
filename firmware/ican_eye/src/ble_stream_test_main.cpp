/**
 * ============================================================================
 * iCan Eye — BLE Stream Test Entry Point
 * Target: Seeed XIAO ESP32-S3 Sense
 * ============================================================================
 *
 * This is a standalone test application to verify the BLE streaming
 * explicitly. It uses dummy data instead of an actual camera frame to isolate
 * BLE throughput and reliability testing from camera stability.
 */

#include <Arduino.h>
#include "ble_eye.h"

// Create a dummy "JPEG" buffer of ~30KB
static const size_t DUMMY_SIZE = 30000;
static uint8_t* dummyImage = nullptr;

void setup() {
  pinMode(21, OUTPUT);
  digitalWrite(21, LOW); // LED ON: Boot started
  
  Serial.begin(115200);
  
  // Wait up to 5 seconds for the PC's Serial Monitor to connect
  uint32_t t = millis();
  while (!Serial && (millis() - t < 5000)) {
      delay(10);
  }
  delay(1000); 

  Serial.println("\n\n===================================");
  Serial.println("iCan Eye - BLE Stream Test Application");
  Serial.println("===================================");
  
  // Blink twice rapidly: Pre-BLE init
  digitalWrite(21, HIGH); delay(100);
  digitalWrite(21, LOW); delay(100);
  digitalWrite(21, HIGH); delay(100);
  digitalWrite(21, LOW); // Stay ON during initBleEye
  
  // Initialize BLE module
  initBleEye();
  
  // Turn OFF LED: BLE Init Successful!
  digitalWrite(21, HIGH);
  
  // Allocate dummy data in PSRAM if available, else heap
  if (psramFound()) {
    dummyImage = (uint8_t*)ps_malloc(DUMMY_SIZE);
  } else {
    dummyImage = (uint8_t*)malloc(DUMMY_SIZE);
  }
  
  if (dummyImage) {
    // Fill with recognizable pattern
    for (size_t i = 0; i < DUMMY_SIZE; i++) {
      dummyImage[i] = (uint8_t)(i % 256);
    }
    Serial.printf("Allocated %u bytes of dummy data.\n", DUMMY_SIZE);
  } else {
    Serial.println("ERROR: Failed to allocate dummy buffer.");
  }
  
  Serial.println("Initialization complete. Waiting for BLE connection...");
  Serial.println("Send 'CAPTURE' over BLE to trigger a dummy stream.");
  Serial.println("===================================\n");
}

void loop() {
  EyeCommandData cmd = getLastEyeCommand();
  
  if (cmd.type == EYE_CMD_CAPTURE) {
    if (isBleEyeConnected() && dummyImage) {
      Serial.println("\n--- STREAMING DUMMY IMAGE ---");
      streamImageViaBle(dummyImage, DUMMY_SIZE, "TEST_PROFILE");
      Serial.println("Stream complete.");
      Serial.println("------------------------");
    } else {
      Serial.println("\nERROR: Cannot stream. Not connected or no memory.");
    }
  }
  
  delay(10);
}
