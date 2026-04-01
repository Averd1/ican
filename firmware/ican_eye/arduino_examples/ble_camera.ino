/*
 * ble_camera.ino — iCan Eye BLE Camera
 * Target: Seeed XIAO ESP32-S3 Sense
 *
 * Captures JPEG photos and sends them over BLE with a reliable
 * chunked protocol (sequence numbers + CRC32 verification).
 *
 * Usage:
 *   1. Open in Arduino IDE with ESP32-S3 board package installed
 *   2. Select board: "XIAO_ESP32S3"
 *   3. Upload
 *   4. Run receive_photo.py on your computer
 *
 * Protocol:
 *   Control characteristic (notify):
 *     ESP32 -> PC:  "SIZE:<bytes>"   — total JPEG size
 *     ESP32 -> PC:  "CRC:<hex>"      — CRC32 of full JPEG buffer
 *     ESP32 -> PC:  "END"            — transfer complete
 *   Control characteristic (write):
 *     PC -> ESP32:  "CAPTURE"        — trigger a photo
 *   Data characteristic (notify):
 *     ESP32 -> PC:  [2-byte seq#][payload]  — image data chunks
 */

#include "esp_camera.h"
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <esp_rom_crc.h>


// ---------- Camera pin definitions ----------
#define CAMERA_MODEL_XIAO_ESP32S3
#include "camera_pins.h"

// ---------- BLE UUIDs ----------
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_DATA "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_CONTROL "beb5483f-36e1-4688-b7f5-ea07361b26a8"

// ---------- Chunk configuration ----------
// Default BLE MTU is 23 bytes (20 usable for ATT payload).
// We use 2 bytes for the sequence number, leaving 18 bytes of image data.
// After MTU negotiation (common on modern OS), we can go larger.
// 182 = 2 (seq) + 180 (data) — safe even without negotiation on most stacks,
// but we request a higher MTU during connection to allow larger packets.
#define SEQ_HEADER_SIZE 2
#define MAX_DATA_PER_CHUNK 180
#define CHUNK_BUF_SIZE (SEQ_HEADER_SIZE + MAX_DATA_PER_CHUNK)

// Flow control
#define CHUNK_DELAY_MS 30  // ms between chunks
#define BURST_SIZE 10      // chunks before a longer pause
#define BURST_PAUSE_MS 100 // longer pause between bursts

BLEServer *pServer = nullptr;
BLECharacteristic *pDataChar = nullptr;
BLECharacteristic *pControlChar = nullptr;
bool deviceConnected = false;
bool takePhoto = false;

// ============================================================
// BLE Callbacks
// ============================================================

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    Serial.println("[BLE] Device connected");
  }
  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println("[BLE] Device disconnected");
    BLEDevice::startAdvertising();
  }
};

class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String val = pChar->getValue().c_str();
    if (val == "CAPTURE") {
      takePhoto = true;
      Serial.println("[BLE] CAPTURE command received");
    }
  }
};

// ============================================================
// Camera
// ============================================================

void startCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_QVGA; // 320x240 — fits BLE transfer
  config.jpeg_quality = 12;           // lower = better quality, bigger file
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_LATEST;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[CAM] Init failed: 0x%x\n", err);
    return;
  }
  Serial.println("[CAM] Camera initialized");

  // Warm-up: take a few throwaway frames so the sensor auto-exposes
  for (int i = 0; i < 3; i++) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (fb)
      esp_camera_fb_return(fb);
    delay(100);
  }
  Serial.println("[CAM] Warm-up complete");
}

// ============================================================
// BLE Photo Transfer
// ============================================================

void sendPhotoViaBLE() {
  // Discard stale frame, keep fresh one
  camera_fb_t *stale = esp_camera_fb_get();
  if (stale)
    esp_camera_fb_return(stale);
  delay(50);

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("[CAM] Capture failed");
    return;
  }

  Serial.printf("[CAM] Photo captured: %u bytes\n", fb->len);

  // --- 1. Compute CRC32 of the raw JPEG ---
  uint32_t crc = esp_rom_crc32_le(0, fb->buf, fb->len);
  Serial.printf("[BLE] CRC32: %08X\n", crc);

  // --- 2. Send SIZE via control characteristic ---
  char ctrlMsg[48];
  snprintf(ctrlMsg, sizeof(ctrlMsg), "SIZE:%u", fb->len);
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();
  delay(200);

  // --- 3. Send CRC via control characteristic ---
  snprintf(ctrlMsg, sizeof(ctrlMsg), "CRC:%08X", crc);
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();
  delay(200);

  // --- 4. Send image data chunks via data characteristic ---
  uint8_t chunkBuf[CHUNK_BUF_SIZE];
  uint16_t seqNum = 0;
  size_t offset = 0;

  while (offset < fb->len) {
    size_t dataLen = fb->len - offset;
    if (dataLen > MAX_DATA_PER_CHUNK)
      dataLen = MAX_DATA_PER_CHUNK;

    // Pack: [seq_lo][seq_hi][data...]
    chunkBuf[0] = (uint8_t)(seqNum & 0xFF);
    chunkBuf[1] = (uint8_t)((seqNum >> 8) & 0xFF);
    memcpy(chunkBuf + SEQ_HEADER_SIZE, fb->buf + offset, dataLen);

    pDataChar->setValue(chunkBuf, SEQ_HEADER_SIZE + dataLen);
    pDataChar->notify();

    offset += dataLen;
    seqNum++;

    // Flow control: pause between chunks, longer pause every BURST_SIZE
    if (seqNum % BURST_SIZE == 0) {
      delay(BURST_PAUSE_MS);
    } else {
      delay(CHUNK_DELAY_MS);
    }
  }

  // --- 5. Send END via control characteristic ---
  delay(300);
  snprintf(ctrlMsg, sizeof(ctrlMsg), "END:%u",
           seqNum); // include total chunk count
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();

  Serial.printf("[BLE] Sent %u chunks (%u bytes)\n", seqNum, fb->len);
  esp_camera_fb_return(fb);
}

// ============================================================
// Setup & Loop
// ============================================================

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== iCan Eye BLE Camera ===");

  startCamera();

  // Initialize BLE
  BLEDevice::init("XIAO_Camera");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Data characteristic — ESP32 sends image chunks here (notify only)
  pDataChar = pService->createCharacteristic(
      CHAR_UUID_DATA, BLECharacteristic::PROPERTY_NOTIFY);
  pDataChar->addDescriptor(new BLE2902());

  // Control characteristic — bidirectional
  //   Write: phone/PC sends "CAPTURE"
  //   Notify: ESP32 sends SIZE, CRC, END messages
  pControlChar = pService->createCharacteristic(
      CHAR_UUID_CONTROL,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  pControlChar->setCallbacks(new ControlCallbacks());
  pControlChar->addDescriptor(new BLE2902());

  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println(
      "[BLE] Advertising as 'XIAO_Camera' — waiting for connection...");
}

void loop() {
  if (deviceConnected && takePhoto) {
    takePhoto = false;
    sendPhotoViaBLE();
  }
  delay(10);
}
