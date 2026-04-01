/**
 * ble_eye.cpp — BLE Peripheral Implementation for iCan Eye
 *
 * Uses the standard ESP32 BLEDevice library (built into the Arduino framework)
 * instead of NimBLE. This avoids the PHY initialization race condition that
 * NimBLE 1.4.1 has with ESP32-S3 + Arduino Core 3.x (ESP-IDF 5.1), where the
 * Bluetooth radio hardware never powers on despite the API returning success.
 *
 * Uses the shared BLE protocol UUIDs and packet structures from
 * ble_protocol.h to ensure consistency with the Cane firmware and
 * the Flutter app.
 */

#include "ble_eye.h"
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <string>
#include <cstdio>
#include "ble_protocol.h"

// =========================================================================
// Internal State
// =========================================================================

static BLEServer *pServer = nullptr;
static BLECharacteristic *pImageStreamChar = nullptr; // image chunks TX
static BLECharacteristic *pInstantTextChar = nullptr; // instant text TX
static BLECharacteristic *pCaptureChar = nullptr;     // capture command RX

static volatile bool clientConnected = false;  // bool read/write is atomic on Xtensa
static uint16_t s_negotiatedMtu = 23;          // BLE default ATT MTU

static portMUX_TYPE s_cmdMux = portMUX_INITIALIZER_UNLOCKED;
static EyeCommand pendingCmdType = EYE_CMD_NONE;
static int pendingCmdProfile = 0;

// =========================================================================
// BLE Callbacks
// =========================================================================

class EyeServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    clientConnected = true;
    s_negotiatedMtu = 23;  // Reset to safe default; updated by onMtuChanged
    Serial.println("[BLE] Client connected. MTU reset to default.");
  }

  void onDisconnect(BLEServer *server) override {
    clientConnected = false;
    Serial.println("[BLE] Client disconnected. Restarting advertising.");
    BLEDevice::startAdvertising();
  }

  void onMtuChanged(BLEServer *server, esp_ble_gatts_cb_param_t *param) override {
    s_negotiatedMtu = param->mtu.mtu;
    Serial.printf("[BLE] MTU updated to %d bytes\n", s_negotiatedMtu);
  }
};

class CaptureCommandCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String cmd = pChar->getValue().c_str();

    if (cmd == "CAPTURE") {
      portENTER_CRITICAL(&s_cmdMux);
      pendingCmdType = EYE_CMD_CAPTURE;
      pendingCmdProfile = 0;
      portEXIT_CRITICAL(&s_cmdMux);
      Serial.println("[BLE] CAPTURE command received");
    } else if (cmd.startsWith("PROFILE:")) {
      int idx = cmd.substring(8).toInt();
      portENTER_CRITICAL(&s_cmdMux);
      pendingCmdType = EYE_CMD_PROFILE;
      pendingCmdProfile = idx;
      portEXIT_CRITICAL(&s_cmdMux);
      Serial.printf("[BLE] PROFILE command received: %d\n", idx);
    } else if (cmd == "STATUS") {
      portENTER_CRITICAL(&s_cmdMux);
      pendingCmdType = EYE_CMD_STATUS;
      pendingCmdProfile = 0;
      portEXIT_CRITICAL(&s_cmdMux);
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
  BLEDevice::init("iCan Eye");
  
  // Allow the BLE stack/radio to stabilize after init
  delay(100);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new EyeServerCallbacks());

  // Create Eye Service
  BLEService *pService = pServer->createService(ICAN_EYE_SERVICE_UUID);

  // Image Stream characteristic — notify image chunks to client
  pImageStreamChar = pService->createCharacteristic(
      CHAR_EYE_IMAGE_STREAM_TX_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  pImageStreamChar->addDescriptor(new BLE2902());

  // Instant Text characteristic — notify quick detection text to client
  pInstantTextChar = pService->createCharacteristic(
      CHAR_EYE_INSTANT_TEXT_TX_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  pInstantTextChar->addDescriptor(new BLE2902());

  // Capture Control characteristic — client writes commands, server notifies status
  pCaptureChar = pService->createCharacteristic(
      CHAR_EYE_CAPTURE_RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  pCaptureChar->setCallbacks(new CaptureCommandCallback());
  pCaptureChar->addDescriptor(new BLE2902());

  // Start the service
  pService->start();

  // Start advertising with scan response to ensure visibility on all platforms
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  
  // Create advertisement data
  BLEAdvertisementData oAdvData = BLEAdvertisementData();
  oAdvData.setFlags(0x06); // General Discoverable, No BR/EDR
  oAdvData.setCompleteServices(BLEUUID(ICAN_EYE_SERVICE_UUID));
  oAdvData.setName("iCan Eye");
  pAdv->setAdvertisementData(oAdvData);

  // Create scan response data (some platforms look here for the name/UUID)
  BLEAdvertisementData oScanResponseData = BLEAdvertisementData();
  oScanResponseData.setCompleteServices(BLEUUID(ICAN_EYE_SERVICE_UUID));
  pAdv->setScanResponseData(oScanResponseData);
  
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06); 
  pAdv->setMaxPreferred(0x12);
  
  pAdv->start();

  Serial.println("[BLE] iCan Eye service advertising.");
}

// =========================================================================
// Public API — Connection & Commands
// =========================================================================

bool isBleEyeConnected() { return clientConnected; }

EyeCommandData getLastEyeCommand() {
  EyeCommandData cmd;
  portENTER_CRITICAL(&s_cmdMux);
  cmd.type = pendingCmdType;
  cmd.profileIndex = pendingCmdProfile;
  pendingCmdType = EYE_CMD_NONE;
  pendingCmdProfile = 0;
  portEXIT_CRITICAL(&s_cmdMux);
  return cmd;
}

// =========================================================================
// Public API — Control Messages
// =========================================================================

void sendControlMessage(const char *msg) {
  if (!clientConnected)
    return;
  pCaptureChar->setValue((uint8_t *)msg, strlen(msg));
  pCaptureChar->notify();
}

// =========================================================================
// Public API — Image Streaming
// =========================================================================

size_t sendImageChunk(uint16_t seqNum, const uint8_t *data, size_t dataLen) {
  if (!clientConnected)
    return 0;

  // Cap payload to negotiated MTU (ATT overhead = 3 bytes) and protocol max
  const size_t mtuPayload = (s_negotiatedMtu > 3 + IMAGE_HEADER_BYTES)
                                ? (s_negotiatedMtu - 3 - IMAGE_HEADER_BYTES)
                                : 0;
  const size_t effectiveMax = (mtuPayload < IMAGE_MAX_PAYLOAD) ? mtuPayload : IMAGE_MAX_PAYLOAD;
  if (dataLen > effectiveMax)
    dataLen = effectiveMax;
  if (dataLen == 0)
    return 0;

  uint8_t chunkBuf[IMAGE_MAX_PACKET_SIZE];

  // Pack header (2 bytes): sequence number (LE)
  chunkBuf[0] = (uint8_t)(seqNum & 0xFF);
  chunkBuf[1] = (uint8_t)((seqNum >> 8) & 0xFF);

  // Copy payload
  memcpy(chunkBuf + IMAGE_HEADER_BYTES, data, dataLen);

  pImageStreamChar->setValue(chunkBuf, IMAGE_HEADER_BYTES + dataLen);
  pImageStreamChar->notify();

  // Must wait long enough for the BLE controller to flush the notification.
  // Windows BLE connection interval is typically 15-30ms.  At 20ms we still
  // lost ~50% of chunks because the TX queue fills faster than it drains.
  // 30ms ensures each notification is transmitted before the next is queued.
  delay(30);
  return dataLen;
}

void streamImageViaBle(const uint8_t *jpegBuf, size_t jpegLen,
                       const char *profileName) {
  if (!clientConnected)
    return;

  Serial.printf("[BLE] Streaming %u bytes (MTU=%u, profile=%s)\n",
                (unsigned)jpegLen, s_negotiatedMtu, profileName);

  // 1. Send SIZE
  char ctrlMsg[32];
  snprintf(ctrlMsg, sizeof(ctrlMsg), "SIZE:%u", (unsigned)jpegLen);
  sendControlMessage(ctrlMsg);
  delay(20);

  // 2. Stream image chunks — offset advances by ACTUAL bytes sent
  uint16_t seqNum = 0;
  size_t offset = 0;

  while (offset < jpegLen) {
    if (!isBleEyeConnected()) {
      Serial.println("[BLE] Client disconnected mid-stream — aborting.");
      return;
    }
    size_t remaining = jpegLen - offset;
    size_t sent = sendImageChunk(seqNum, jpegBuf + offset, remaining);
    if (sent == 0)
      break; // MTU too small or disconnected
    offset += sent;
    seqNum++;
    if (seqNum % 10 == 0) {
      Serial.printf("[BLE] Progress: chunk %u, %u/%u bytes\n",
                    seqNum, (unsigned)offset, (unsigned)jpegLen);
    }
  }

  // 3. Send END
  delay(20);
  snprintf(ctrlMsg, sizeof(ctrlMsg), "END:%u", seqNum);
  sendControlMessage(ctrlMsg);

  Serial.printf("[BLE] Sent %u chunks (%u bytes)\n", seqNum,
                (unsigned)jpegLen);
}

