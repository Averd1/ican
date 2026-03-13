/**
 * GPS Module Test Application
 * 
 * Target: Arduino Nano ESP32
 * 
 * This is a standalone test application to verify the GPS module
 * functionality without running the full iCan Cane firmware.
 * It initializes the GPS and prints detailed fix information to
 * the Serial monitor every 2 seconds.
 */

#include <Arduino.h>
#include <Wire.h>
#include "gps.h"

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  Serial.println("\n\n===================================");
  Serial.println("iCan Cane - GPS Test Application");
  Serial.println("===================================");
  
  // Initialize the GPS module
  // This will configure Hardware Serial 2 (RX=16, TX=17) 
  // and send the initialization commands to the module.
  initGPS();
  
  Serial.println("Initialization complete. Waiting for first fix...");
  Serial.println("Note: A cold start indoors may take several minutes to get a fix.");
  Serial.println("===================================\n");
}

void loop() {
  // pollGPS() MUST be called every loop iteration to drain the serial buffer
  // and parse incoming NMEA sentences. It is non-blocking.
  pollGPS();

  // Every 2 seconds, print the latest GPS data
  static uint32_t lastPrintTime = 0;
  uint32_t now = millis();
  
  if (now - lastPrintTime >= 2000) {
    lastPrintTime = now;
    
    // getGPSData() returns a snapshot of the most recent parsed data
    GpsData data = getGPSData();
    
    if (data.fix) {
      Serial.println("\n--- GPS FIX ACQUIRED ---");
      Serial.printf("Location:   %.6f, %.6f\n", data.latitude, data.longitude);
      Serial.printf("Altitude:   %.1f meters\n", data.altitudeM);
      Serial.printf("Speed:      %.2f knots\n", data.speedKnots);
      Serial.printf("Heading:    %.2f degrees\n", data.angleDeg);
      Serial.printf("Satellites: %d\n", data.satellites);
      Serial.printf("Fix Qual:   %d\n", data.fixQuality);
      Serial.println("------------------------");
    } else {
      Serial.print("."); // Show activity while waiting for a fix
    }
  }
}
