/**
 * ble_eye.h — BLE Peripheral Communication Layer for iCan Eye
 *
 * Sets up the BLE server on the XIAO ESP32-S3 with the iCan Eye service
 * and characteristics defined in ble_protocol.h.
 *
 * Provides a high-level API: init, send photo, handle commands.
 */

#ifndef BLE_EYE_H
#define BLE_EYE_H

#include "ble_protocol.h"
#include <stddef.h>
#include <stdint.h>

// =========================================================================
// Command callback — called when a BLE client sends a command
// =========================================================================

/** Command types the Eye can receive. */
enum EyeCommand : uint8_t {
  EYE_CMD_NONE = 0,
  EYE_CMD_CAPTURE = 1,
  EYE_CMD_PROFILE = 2,
  EYE_CMD_STATUS = 3,
};

/** Parsed command from BLE client. */
struct EyeCommandData {
  EyeCommand type;
  int profileIndex; // only valid when type == EYE_CMD_PROFILE
};

// =========================================================================
// Public API
// =========================================================================

/**
 * Initialize BLE peripheral with the iCan Eye service.
 * Creates characteristics for image streaming and capture control.
 * Starts advertising as "iCan Eye".
 */
void initBleEye();

/**
 * Check if a BLE client (phone/PC) is currently connected.
 */
bool isBleEyeConnected();

/**
 * Get the last command received from the BLE client.
 * Returns EYE_CMD_NONE if no command pending.
 * Calling this clears the pending command.
 */
EyeCommandData getLastEyeCommand();

/**
 * Send a status/control message to the connected client via the
 * control (capture) characteristic as a notify.
 * Examples: "SIZE:12345", "CRC:AABBCCDD", "END:42"
 */
void sendControlMessage(const char *msg);

/**
 * Send a single image data chunk to the connected client.
 * Packs the sequence number header and payload per ble_protocol.h.
 *
 * @param seqNum   Chunk sequence number (0-based).
 * @param data     Pointer to JPEG data for this chunk.
 * @param dataLen  Number of payload bytes (max IMAGE_MAX_PAYLOAD = 235).
 */
void sendImageChunk(uint16_t seqNum, const uint8_t *data, size_t dataLen);

/**
 * High-level: stream an entire JPEG buffer over BLE with flow control.
 * Sends SIZE, CRC, image chunks, and END messages automatically.
 *
 * @param jpegBuf   Pointer to JPEG data.
 * @param jpegLen   Length of JPEG data in bytes.
 * @param profileName  Name of the profile used (sent as INFO message).
 */
void streamImageViaBle(const uint8_t *jpegBuf, size_t jpegLen,
                       const char *profileName);

#endif // BLE_EYE_H
