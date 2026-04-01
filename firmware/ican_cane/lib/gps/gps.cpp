/**
 * gps.cpp — GPS Module Implementation
 *
 * Target: Arduino Nano ESP32 OR WROOM ESP32 Dev Board
 * Hardware: Adafruit Mini GPS PA1010D (or any MTK3333-based module)
 * Interface: UART via Hardware Serial 2
 */

#include "gps.h"
#include <Adafruit_GPS.h>
#include <Arduino.h>
#include <HardwareSerial.h>

// ---------------------------------------------------------------------------
// Pin Definitions
// ---------------------------------------------------------------------------

/** GPIO connected to GPS module TX (module sends, ESP32 receives) */
constexpr int GPS_RX_PIN = 16;

/** GPIO connected to GPS module RX (ESP32 sends commands, module receives) */
constexpr int GPS_TX_PIN = 17;

/** UART baud rate — standard for MTK3333-based GPS modules */
constexpr uint32_t GPS_BAUD = 9600;

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

static HardwareSerial gpsSerial(2); // Hardware Serial 2
static Adafruit_GPS gps(&gpsSerial);
static GpsData latestData = {};

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

/**
 * Convert raw NMEA coordinate (DDDMM.MMMMM) + hemisphere char to
 * signed decimal degrees.
 *
 *  e.g. lat=4807.038, hemi='N'  →  48.1173°
 *       lon=01131.000, hemi='W' → -11.5167°
 */
static float nmeaToDecimalDeg(float nmeaCoord, char hemisphere) {
  int degrees = (int)(nmeaCoord / 100);
  float minutes = nmeaCoord - (degrees * 100.0f);
  float decimal = degrees + (minutes / 60.0f);
  if (hemisphere == 'S' || hemisphere == 'W') {
    decimal = -decimal;
  }
  return decimal;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void initGPS() {
  // Begin GPS serial — Adafruit_GPS constructor accepted a pointer to
  // gpsSerial; calling GPS.begin() will call gpsSerial.begin() internally.
  // We pass RX/TX pins here so the HardwareSerial knows which GPIOs to use
  // before GPS.begin() triggers the underlying begin().
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  gps.begin(GPS_BAUD); // Adafruit_GPS re-calls begin() — harmless on ESP32

  // Output: RMC (recommended minimum) + GGA (fix quality & altitude)
  gps.sendCommand(PMTK_SET_NMEA_OUTPUT_RMCGGA);

  // Update rate: 1 Hz (sufficient for navigation; safe for MTK3333)
  gps.sendCommand(PMTK_SET_NMEA_UPDATE_1HZ);

  // Request antenna status reports (useful for debugging fix issues)
  gps.sendCommand(PGCMD_ANTENNA);

  Serial.println("[GPS] Initialized on Serial2 (RX=16, TX=17) @ 9600 baud.");
  Serial.println("[GPS] Waiting for fix...");

  delay(500); // Give module time to process commands before first poll
}

void pollGPS() {
  // Read all available bytes — non-blocking, must be called every loop()
  gps.read();

  if (gps.newNMEAreceived()) {
    // parse() resets newNMEAreceived flag; returns false if sentence is garbled
    if (!gps.parse(gps.lastNMEA())) {
      return; // Discard corrupt sentence, wait for next one
    }

    // Update our snapshot from the freshly parsed sentence
    latestData.fix = gps.fix;
    latestData.fixQuality = gps.fixquality;
    latestData.satellites = gps.satellites;

    if (gps.fix) {
      // Convert NMEA DDDMM.MMMM format to signed decimal degrees
      latestData.latitude = nmeaToDecimalDeg(gps.latitude, gps.lat);
      latestData.longitude = nmeaToDecimalDeg(gps.longitude, gps.lon);
      latestData.speedKnots = gps.speed;
      latestData.angleDeg = gps.angle;
      latestData.altitudeM = gps.altitude;
    }
  }
}

GpsData getGPSData() { return latestData; }

bool hasGPSFix() { return latestData.fix; }
