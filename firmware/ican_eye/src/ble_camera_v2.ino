/*
 * ble_camera_v2.ino — iCan Eye BLE Camera (V2 — Tunable Quality)
 * Target: Seeed XIAO ESP32-S3 Sense (OV2640, 8MB PSRAM)
 *
 * V2 improvements over V1:
 *   - 4 selectable quality profiles via BLE commands
 *   - Larger chunks (up to 240 bytes data) for faster transfer at MTU 256
 *   - Higher resolutions up to UXGA (1600x1200)
 *   - PSRAM-aware frame buffer allocation
 *   - Per-profile JPEG quality tuning
 *
 * BLE Commands (write to Control characteristic):
 *   "CAPTURE"     — take photo with current profile (default: BALANCED)
 *   "PROFILE:0"   — FAST     (QVGA  320x240,  quality 15, ~3-5 KB, ~2s
 * transfer) "PROFILE:1"   — BALANCED (VGA   640x480,  quality 12, ~15-25 KB,
 * ~8s transfer) "PROFILE:2"   — QUALITY  (SVGA  800x600,  quality 10, ~30-50
 * KB, ~15s transfer) "PROFILE:3"   — MAX      (UXGA  1600x1200, quality 10,
 * ~80-150 KB, ~45s transfer) "STATUS"       — prints current profile over
 * Serial (debug)
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
// With negotiated MTU 256, ATT payload is up to 253 bytes.
// We use 2 bytes for the sequence number → 240 bytes of image data per chunk.
// Falls back gracefully to smaller effective size if MTU stays at default 23.
#define SEQ_HEADER_SIZE 2
#define MAX_DATA_PER_CHUNK 240
#define CHUNK_BUF_SIZE (SEQ_HEADER_SIZE + MAX_DATA_PER_CHUNK)

// Flow control — tuned to prevent BLE notification queue overflow
#define CHUNK_DELAY_MS 40  // ms between chunks (was 25 — too fast)
#define BURST_SIZE 8       // chunks before a longer pause (was 15)
#define BURST_PAUSE_MS 150 // longer pause between bursts (was 80)

// ============================================================
// Quality Profiles
// ============================================================

struct CameraProfile {
  const char *name;
  framesize_t frameSize;
  int jpegQuality; // 0-63, lower = better quality, bigger file
};

// Profile table — indexed by profile number
// Quality values bumped up to keep file sizes manageable over BLE
const CameraProfile profiles[] = {
    {"FAST", FRAMESIZE_QVGA, 18},    // 0: 320x240  ~2-4 KB
    {"BALANCED", FRAMESIZE_VGA, 15}, // 1: 640x480  ~10-20 KB
    {"QUALITY", FRAMESIZE_SVGA, 12}, // 2: 800x600  ~20-40 KB
    {"MAX", FRAMESIZE_UXGA, 12},     // 3: 1600x1200 ~50-100 KB
};
const int NUM_PROFILES = sizeof(profiles) / sizeof(profiles[0]);

int currentProfile = 1; // default: BALANCED

// ============================================================
// BLE State
// ============================================================

BLEServer *pServer = nullptr;
BLECharacteristic *pDataChar = nullptr;
BLECharacteristic *pControlChar = nullptr;
bool deviceConnected = false;
bool takePhoto = false;

// ============================================================
// Apply a camera profile (changes resolution + quality on the fly)
// ============================================================

void applyProfile(int idx) {
  if (idx < 0 || idx >= NUM_PROFILES)
    return;
  currentProfile = idx;

  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_framesize(s, profiles[idx].frameSize);
    s->set_quality(s, profiles[idx].jpegQuality);
    Serial.printf("[CAM] Profile set: %s (quality=%d)\n", profiles[idx].name,
                  profiles[idx].jpegQuality);
  }

  // Take a throwaway frame so the new settings take effect
  camera_fb_t *fb = esp_camera_fb_get();
  if (fb)
    esp_camera_fb_return(fb);
  delay(100);
}

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
    } else if (val.startsWith("PROFILE:")) {
      int idx = val.substring(8).toInt();
      if (idx >= 0 && idx < NUM_PROFILES) {
        applyProfile(idx);
        // Notify the PC of the profile change
        char msg[64];
        snprintf(msg, sizeof(msg), "PROFILE_SET:%d:%s", idx,
                 profiles[idx].name);
        pControlChar->setValue((uint8_t *)msg, strlen(msg));
        pControlChar->notify();
      } else {
        Serial.printf("[BLE] Invalid profile: %d\n", idx);
      }
    } else if (val == "STATUS") {
      Serial.printf("[INFO] Current profile: %d (%s)\n", currentProfile,
                    profiles[currentProfile].name);
    } else {
      Serial.printf("[BLE] Unknown command: %s\n", val.c_str());
    }
  }
};

// ============================================================
// Camera Init
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

  // Start at BALANCED profile resolution
  config.frame_size = profiles[currentProfile].frameSize;
  config.jpeg_quality = profiles[currentProfile].jpegQuality;

  // Always use 1 frame buffer + GRAB_WHEN_EMPTY.
  // GRAB_LATEST with fb_count=2 causes FB-OVF when exposure is high
  // because the camera fills buffers faster than we consume them.
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  if (psramFound()) {
    Serial.printf("[CAM] PSRAM found: %d bytes free\n", ESP.getFreePsram());
  } else {
    Serial.println("[CAM] No PSRAM detected");
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[CAM] Init failed: 0x%x\n", err);
    return;
  }

  // OV2640 sensor tweaks — bright but stable (no FB-OVF)
  // Note: aec_value removed — it forces long exposures that stall frame
  // delivery
  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 2); // -2 to 2, MAX brightness
    s->set_contrast(s, 1);   // -2 to 2, slight boost
    s->set_saturation(s, 0); // -2 to 2
    s->set_whitebal(s, 1);   // auto white balance on
    s->set_awb_gain(s, 1);   // AWB gain on
    s->set_wb_mode(s, 0);    // 0=auto, 1=sunny, 2=cloudy, 3=office, 4=home
    s->set_aec2(s, 1);       // auto exposure control (DSP) on
    s->set_ae_level(s, 2);   // -2 to 2, MAX exposure compensation
    s->set_gainceiling(s, GAINCEILING_16X); // max gain for dark areas
  }

  Serial.printf("[CAM] Initialized — profile: %s\n",
                profiles[currentProfile].name);

  // Warm-up: 6 frames with 300ms gap so auto-exposure can fully settle
  // Longer delay prevents FB-OVF during init
  for (int i = 0; i < 6; i++) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (fb)
      esp_camera_fb_return(fb);
    delay(300);
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

  Serial.printf("[CAM] Photo captured: %u bytes (%s)\n", fb->len,
                profiles[currentProfile].name);

  // --- 1. Compute CRC32 ---
  uint32_t crc = esp_rom_crc32_le(0, fb->buf, fb->len);
  Serial.printf("[BLE] CRC32: %08X\n", crc);

  // --- 2. Send SIZE via control characteristic ---
  char ctrlMsg[64];
  snprintf(ctrlMsg, sizeof(ctrlMsg), "SIZE:%u", fb->len);
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();
  delay(150);

  // --- 3. Send CRC via control characteristic ---
  snprintf(ctrlMsg, sizeof(ctrlMsg), "CRC:%08X", crc);
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();
  delay(150);

  // --- 4. Send PROFILE info so receiver knows what was used ---
  snprintf(ctrlMsg, sizeof(ctrlMsg), "INFO:%s", profiles[currentProfile].name);
  pControlChar->setValue((uint8_t *)ctrlMsg, strlen(ctrlMsg));
  pControlChar->notify();
  delay(150);

  // --- 5. Send image data chunks via data characteristic ---
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

    // Flow control
    if (seqNum % BURST_SIZE == 0) {
      delay(BURST_PAUSE_MS);
    } else {
      delay(CHUNK_DELAY_MS);
    }
  }

  // --- 6. Send END via control characteristic ---
  delay(300);
  snprintf(ctrlMsg, sizeof(ctrlMsg), "END:%u", seqNum);
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
  Serial.println("\n=== iCan Eye BLE Camera V2 ===");

  startCamera();

  // Initialize BLE
  BLEDevice::init("XIAO_Camera");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Data characteristic — image chunks (notify)
  pDataChar = pService->createCharacteristic(
      CHAR_UUID_DATA, BLECharacteristic::PROPERTY_NOTIFY);
  pDataChar->addDescriptor(new BLE2902());

  // Control characteristic — commands + status (write + notify)
  pControlChar = pService->createCharacteristic(
      CHAR_UUID_CONTROL,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  pControlChar->setCallbacks(new ControlCallbacks());
  pControlChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println(
      "[BLE] Advertising as 'XIAO_Camera' — waiting for connection...");
  Serial.printf("[BLE] Default profile: %d (%s)\n", currentProfile,
                profiles[currentProfile].name);
}

void loop() {
  if (deviceConnected && takePhoto) {
    takePhoto = false;
    sendPhotoViaBLE();
  }
  delay(10);
}
