/**
 * ble_comm.h — BLE Peripheral Communication Layer (NimBLE)
 *
 * Sets up the BLE server on the Arduino Nano ESP32 with the iCan Cane
 * service and characteristics defined in ble_protocol.h.
 */

#ifndef BLE_COMM_H
#define BLE_COMM_H

#include "ble_protocol.h"
#include "gps.h"
#include <stdint.h>

/**
 * Initialize BLE peripheral with the iCan Cane service.
 * Creates characteristics for nav commands, obstacle alerts, and telemetry.
 * Starts advertising.
 */
void initBleCane();

/**
 * Get the last navigation command received from the app.
 * Returns NAV_STOP if no command pending.
 * Calling this clears the pending command.
 */
NavCommand getLastNavCommand();

/**
 * Send an obstacle alert notification to the connected app.
 *
 * @param side     Which side the obstacle was detected on.
 * @param distCm   Distance in centimeters.
 */
void notifyObstacle(ObstacleSide side, uint16_t distCm);

/**
 * Send a telemetry packet notification to the connected app.
 */
void sendTelemetry(const TelemetryPacket &pkt);

/**
 * Send a GPS data packet notification to the connected app.
 * Transmits latitude, longitude, altitude, speed, satellite count, and fix status.
 */
void sendGpsData(const GpsData &data);

/**
 * Check if a BLE client (phone) is currently connected.
 */
bool isBleConnected();

#endif // BLE_COMM_H
