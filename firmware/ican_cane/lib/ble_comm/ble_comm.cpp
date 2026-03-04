/**
 * ble_comm.cpp — BLE Peripheral Implementation (NimBLE)
 */

#include "ble_comm.h"
#include <NimBLECharacteristic.h>
#include <NimBLEDevice.h>


// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------
static NimBLEServer *pServer = nullptr;
static NimBLECharacteristic *pNavCommandChar = nullptr;
static NimBLECharacteristic *pObstacleChar = nullptr;
static NimBLECharacteristic *pTelemetryChar = nullptr;
static NimBLECharacteristic *pStatusChar = nullptr;

static volatile NavCommand pendingNavCmd = NAV_STOP;
static volatile bool clientConnected = false;

// ---------------------------------------------------------------------------
// BLE Callbacks
// ---------------------------------------------------------------------------

class CaneServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *server, NimBLEConnInfo &connInfo) override {
    clientConnected = true;
    Serial.println("[BLE] Client connected.");
    // Request higher MTU for better throughput
    server->updateConnParams(connInfo.getConnHandle(), 12, 24, 0, 200);
  }

  void onDisconnect(NimBLEServer *server, NimBLEConnInfo &connInfo,
                    int reason) override {
    clientConnected = false;
    Serial.printf(
        "[BLE] Client disconnected (reason=%d). Restarting advertising.\n",
        reason);
    NimBLEDevice::startAdvertising();
  }
};

class NavCommandCallback : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pChar, NimBLEConnInfo &connInfo) override {
    NimBLEAttValue val = pChar->getValue();
    const uint8_t *data = val.data();
    size_t len = val.size();
    if (len >= 1) {
      pendingNavCmd = static_cast<NavCommand>(data[0]);
      Serial.printf("[BLE] Nav command received: 0x%02X\n", data[0]);
    }
  }
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void initBleCane() {
  NimBLEDevice::init("iCan Cane");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Max power for range

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new CaneServerCallbacks());

  // Create Cane Service
  NimBLEService *pService = pServer->createService(ICAN_CANE_SERVICE_UUID);

  // Nav Command (write by app)
  pNavCommandChar = pService->createCharacteristic(
      CHAR_NAV_COMMAND_RX_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  pNavCommandChar->setCallbacks(new NavCommandCallback());

  // Obstacle Alert (notify to app)
  pObstacleChar = pService->createCharacteristic(CHAR_OBSTACLE_ALERT_TX_UUID,
                                                 NIMBLE_PROPERTY::NOTIFY);

  // IMU Telemetry (notify to app)
  pTelemetryChar = pService->createCharacteristic(CHAR_IMU_TELEMETRY_TX_UUID,
                                                  NIMBLE_PROPERTY::NOTIFY);

  // Cane Status (read by app)
  pStatusChar = pService->createCharacteristic(CHAR_CANE_STATUS_TX_UUID,
                                               NIMBLE_PROPERTY::READ);
  // Set initial status: battery 100%, version 1.0, all sensors OK
  uint8_t statusData[] = {100, 1, 0, 0xFF};
  pStatusChar->setValue((const uint8_t *)statusData, sizeof(statusData));

  pService->start();

  // Start advertising
  NimBLEAdvertising *pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(ICAN_CANE_SERVICE_UUID);
  pAdv->enableScanResponse(true);
  pAdv->start();

  Serial.println("[BLE] iCan Cane service advertising.");
}

NavCommand getLastNavCommand() {
  NavCommand cmd = pendingNavCmd;
  pendingNavCmd = NAV_STOP; // Clear after read
  return cmd;
}

void notifyObstacle(ObstacleSide side, uint16_t distCm) {
  if (!clientConnected)
    return;

  uint8_t data[3];
  data[0] = static_cast<uint8_t>(side);
  data[1] = distCm & 0xFF;        // low byte
  data[2] = (distCm >> 8) & 0xFF; // high byte
  pObstacleChar->setValue((const uint8_t *)data, sizeof(data));
  pObstacleChar->notify();
}

void sendTelemetry(const TelemetryPacket &pkt) {
  if (!clientConnected)
    return;

  pTelemetryChar->setValue(reinterpret_cast<const uint8_t *>(&pkt),
                           sizeof(pkt));
  pTelemetryChar->notify();
}

bool isBleConnected() { return clientConnected; }
