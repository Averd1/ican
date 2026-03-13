/**
 * gps.h — GPS Module Interface
 *
 * Wraps the Adafruit GPS library (Adafruit_GPS) for use with the iCan Cane.
 * Uses Hardware Serial 2 on the Arduino Nano ESP32 (GPIO 16 RX, GPIO 17 TX).
 *
 * Call initGPS() once in setup(), then pollGPS() every loop iteration.
 * Data is available via getGPSData() when a fix is acquired.
 */

#ifndef GPS_H
#define GPS_H

#include <stdbool.h>
#include <stdint.h>


// ---------------------------------------------------------------------------
// GPS Data Structure
// ---------------------------------------------------------------------------

/**
 * Snapshot of the latest parsed GPS fix.
 * Coordinates are in decimal degrees (standard float representation).
 */
struct GpsData {
  bool fix;           // true if a valid fix has been acquired
  float latitude;     // decimal degrees (positive = N, negative = S)
  float longitude;    // decimal degrees (positive = E, negative = W)
  float speedKnots;   // speed over ground in knots
  float angleDeg;     // track angle in degrees (true north)
  float altitudeM;    // altitude in meters above mean sea level
  uint8_t satellites; // number of satellites in use
  uint8_t fixQuality; // 0 = invalid, 1 = GPS fix, 2 = DGPS fix
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Initialize the GPS module.
 * Configures Hardware Serial 2 and sends NMEA command strings.
 * Must be called once in setup().
 */
void initGPS();

/**
 * Poll the GPS module — must be called every loop() iteration.
 * Reads available bytes from the serial buffer and parses complete
 * NMEA sentences. Non-blocking.
 */
void pollGPS();

/**
 * Returns a snapshot of the most recently parsed GPS data.
 * Check GpsData.fix before trusting coordinate fields.
 */
GpsData getGPSData();

/**
 * Returns true if a valid GPS fix is currently held.
 * Convenience wrapper around getGPSData().fix.
 */
bool hasGPSFix();

#endif // GPS_H
