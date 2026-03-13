/**
 * ble_eye.cpp — BLE Peripheral Implementation for iCan Eye (NimBLE)
 *
 * Uses the shared BLE protocol UUIDs and packet structures from
 * ble_protocol.h to ensure consistency with the Cane firmware and
 * the Flutter app.
 */

#include "ble_eye.h"
#include <Arduino.h>
#include <NimBLECharacteristic.h>
#include <NimBLEDevice.h>
#include <esp_rom_crc.h>
#include <string>
#include <stdio.h>
#include "ble_protocol.h"

// =========================================================================
// Internal State
// =========================================================================

static NimBLEServer *pServer = nullptr;
static NimBLECharacteristic *pImageStreamChar = nullptr; // image chunks TX
static NimBLECharacteristic *pInstantTextChar = nullptr; // instant text TX
static NimBLECharacteristic *pCaptureChar = nullptr;     // capture command RX

static volatile bool clientConnected = false;
static volatile EyeCommand pendingCmdType = EYE_CMD_NONE;
static volatile int pendingCmdProfile = 0;

// =========================================================================
// Flow Control Tuning
// =========================================================================

static constexpr uint8_t CHUNK_DELAY_MS = 40;
static constexpr uint8_t BURST_SIZE = 8;
static constexpr uint8_t BURST_PAUSE_MS = 150;

// =========================================================================
// BLE Callbacks
// =========================================================================

class EyeServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *server, NimBLEConnInfo &connInfo) override {
    clientConnected = true;
    Serial.println("[BLE] Client connected");
  }

  void onDisconnect(NimBLEServer *server, NimBLEConnInfo &connInfo,
                    int reason) override {
    clientConnected = false;
    Serial.printf("[BLE] Client disconnected (reason=%d). Restarting "
                  "advertising.\n",
                  reason);
    NimBLEDevice::startAdvertising();
  }
};

class CaptureCommandCallback : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pChar,
               NimBLEConnInfo &connInfo) override {
    NimBLEAttValue val = pChar->getValue();
    std::string cmd_str((const char *)val.data(), val.size());
    String cmd(cmd_str.c_str());

    if (cmd == "CAPTURE") {
      pendingCmdType = EYE_CMD_CAPTURE;
      pendingCmdProfile = 0;
      Serial.println("[BLE] CAPTURE command received");
    } else if (cmd.startsWith("PROFILE:")) {
      int idx = cmd.substring(8).toInt();
      pendingCmdType = EYE_CMD_PROFILE;
      pendingCmdProfile = idx;
      Serial.printf("[BLE] PROFILE command received: %d\n", idx);
    } else if (cmd == "STATUS") {
      pendingCmdType = EYE_CMD_STATUS;
      pendingCmdProfile = 0;
      Serial.println("[BLE] STATUS command received");
    } else {
      Serial.printf("[BLE] Unknown command: %s\n", cmd.c_str());
    }
  }
};

// =========================================================================
// Public API — Init
// =========================================================================

void initBleEye() {
  NimBLEDevice::init("iCan Eye");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new EyeServerCallbacks());

  // Create Eye Service
  NimBLEService *pService = pServer->createService(NimBLEUUID(ICAN_EYE_SERVICE_UUID));

  // Image Stream characteristic — notify image chunks to client
  pImageStreamChar = pService->createCharacteristic(
      NimBLEUUID(CHAR_EYE_IMAGE_STREAM_TX_UUID), (uint32_t)NIMBLE_PROPERTY::NOTIFY);

  // Instant Text characteristic — notify quick detection text to client
  pInstantTextChar = pService->createCharacteristic(
      NimBLEUUID(CHAR_EYE_INSTANT_TEXT_TX_UUID), (uint32_t)NIMBLE_PROPERTY::NOTIFY);

  // Capture Control characteristic — client writes commands, server notifies status
  pCaptureChar = pService->createCharacteristic(
      NimBLEUUID(CHAR_EYE_CAPTURE_RX_UUID),
      (uint32_t)(NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY));
  pCaptureChar->setCallbacks(new CaptureCommandCallback());

  pService->start();

  // Start advertising
  NimBLEAdvertising *pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(NimBLEUUID(ICAN_EYE_SERVICE_UUID));
  pAdv->enableScanResponse(true);
  pAdv->start();

  Serial.println("[BLE] iCan Eye service advertising.");
}

// =========================================================================
// Public API — Connection & Commands
// =========================================================================

bool isBleEyeConnected() { return clientConnected; }

EyeCommandData getLastEyeCommand() {
  EyeCommandData cmd;
  cmd.type = (EyeCommand)pendingCmdType;
  cmd.profileIndex = pendingCmdProfile;
  pendingCmdType = EYE_CMD_NONE;
  pendingCmdProfile = 0;
  return cmd;
}

// =========================================================================
// Public API — Control Messages
// =========================================================================

void sendControlMessage(const char *msg) {
  if (!clientConnected)
    return;
  pCaptureChar->setValue((const uint8_t *)msg, strlen(msg));
  pCaptureChar->notify();
}

// =========================================================================
// Public API — Image Streaming
// =========================================================================

void sendImageChunk(uint16_t seqNum, const uint8_t *data, size_t dataLen) {
  if (!clientConnected)
    return;

  uint8_t chunkBuf[IMAGE_MAX_PACKET_SIZE];

  // Pack header per ble_protocol.h ImagePacketHeader layout
  chunkBuf[0] = (uint8_t)(seqNum & 0xFF);
  chunkBuf[1] = (uint8_t)((seqNum >> 8) & 0xFF);

  // Copy payload
  if (dataLen > IMAGE_MAX_PAYLOAD)
    dataLen = IMAGE_MAX_PAYLOAD;
  memcpy(chunkBuf + IMAGE_HEADER_BYTES, data, dataLen);

  pImageStreamChar->setValue(chunkBuf, IMAGE_HEADER_BYTES + dataLen);
  pImageStreamChar->notify();
}

void streamImageViaBle(const uint8_t *jpegBuf, size_t jpegLen,
                       const char *profileName) {
  if (!clientConnected)
    return;

  // 1. Compute CRC32
  uint32_t crc = esp_rom_crc32_le(0, jpegBuf, jpegLen);
  Serial.printf("[BLE] CRC32: %08X\n", crc);

  // 2. Send SIZE
  char ctrlMsg[64];
  snprintf(ctrlMsg, sizeof(ctrlMsg), "SIZE:%u", (unsigned int)jpegLen);
  sendControlMessage(ctrlMsg);
  delay(150);

  // 3. Send CRC
  snprintf(ctrlMsg, sizeof(ctrlMsg), "CRC:%08X", crc);
  sendControlMessage(ctrlMsg);
  delay(150);

  // 4. Send profile INFO
  snprintf(ctrlMsg, sizeof(ctrlMsg), "INFO:%s", profileName);
  sendControlMessage(ctrlMsg);
  delay(150);

  // 5. Stream image chunks
  uint16_t seqNum = 0;
  size_t offset = 0;

  while (offset < jpegLen) {
    size_t chunkLen = jpegLen - offset;
    if (chunkLen > IMAGE_MAX_PAYLOAD)
      chunkLen = IMAGE_MAX_PAYLOAD;

    sendImageChunk(seqNum, jpegBuf + offset, chunkLen);

    offset += chunkLen;
    seqNum++;

    // Flow control
    if (seqNum % BURST_SIZE == 0) {
      delay(BURST_PAUSE_MS);
    } else {
      delay(CHUNK_DELAY_MS);
    }
  }

  // 6. Send END
  delay(300);
  snprintf(ctrlMsg, sizeof(ctrlMsg), "END:%u", seqNum);
  sendControlMessage(ctrlMsg);

  Serial.printf("[BLE] Sent %u chunks (%u bytes)\n", seqNum,
                (unsigned int)jpegLen);
}


