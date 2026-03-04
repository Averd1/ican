/**
 * ============================================================================
 * iCan Eye — Main Firmware Entry Point
 * Target: Seeed XIAO ESP32-S3 Sense
 * ============================================================================
 *
 * On button press:
 *   Pipeline 1: Run local TFLite model → send text label via BLE GATT
 *   Pipeline 2: Capture JPEG → chunk → stream via BLE to phone
 *
 * The phone-side app reassembles the image and runs a VLM for rich
 * scene description.
 * ============================================================================
 */

#include "ble_protocol.h"
#include "esp_camera.h"
#include <Arduino.h>
#include <NimBLEDevice.h>


// ---------------------------------------------------------------------------
// XIAO ESP32-S3 Sense Camera Pin Definitions
// ---------------------------------------------------------------------------
#define PWDN_GPIO_NUM -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 10
#define SIOD_GPIO_NUM 40
#define SIOC_GPIO_NUM 39
#define Y9_GPIO_NUM 48
#define Y8_GPIO_NUM 11
#define Y7_GPIO_NUM 12
#define Y6_GPIO_NUM 14
#define Y5_GPIO_NUM 16
#define Y4_GPIO_NUM 18
#define Y3_GPIO_NUM 17
#define Y2_GPIO_NUM 15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM 47
#define PCLK_GPIO_NUM 13

// Button pin (built-in user button on XIAO)
constexpr uint8_t PIN_BUTTON = 0;

// ---------------------------------------------------------------------------
// BLE State
// ---------------------------------------------------------------------------
static NimBLEServer *pServer = nullptr;
static NimBLECharacteristic *pInstantText = nullptr;
static NimBLECharacteristic *pImageStream = nullptr;
static NimBLECharacteristic *pCaptureCmd = nullptr;
static volatile bool bleConnected = false;
static volatile bool captureRequest = false;

// ---------------------------------------------------------------------------
// BLE Callbacks
// ---------------------------------------------------------------------------

class EyeServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &connInfo) override {
    bleConnected = true;
    Serial.println("[BLE] Phone connected.");
  }
  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &connInfo,
                    int reason) override {
    bleConnected = false;
    Serial.println("[BLE] Phone disconnected. Re-advertising.");
    NimBLEDevice::startAdvertising();
  }
};

class CaptureCallback : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pChar, NimBLEConnInfo &connInfo) override {
    captureRequest = true;
    Serial.println("[BLE] Remote capture request received.");
  }
};

// ---------------------------------------------------------------------------
// Camera Init
// ---------------------------------------------------------------------------
bool initCamera() {
  camera_config_t config = {};
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
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA; // 640×480
  config.jpeg_quality = 12;          // 0-63, lower = better quality
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_LATEST;

  // Use PSRAM for frame buffer
  if (psramFound()) {
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.fb_count = 2;
    Serial.println("[Camera] PSRAM detected, using 2 frame buffers.");
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[Camera] Init failed: 0x%x\n", err);
    return false;
  }

  Serial.println("[Camera] Initialized OK (VGA JPEG).");
  return true;
}

// ---------------------------------------------------------------------------
// BLE Init
// ---------------------------------------------------------------------------
void initBleEye() {
  NimBLEDevice::init("iCan Eye");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new EyeServerCallbacks());

  NimBLEService *pService = pServer->createService(ICAN_EYE_SERVICE_UUID);

  // Pipeline 1: Instant text result
  pInstantText = pService->createCharacteristic(CHAR_EYE_INSTANT_TEXT_TX_UUID,
                                                NIMBLE_PROPERTY::NOTIFY);

  // Pipeline 2: Image stream
  pImageStream = pService->createCharacteristic(CHAR_EYE_IMAGE_STREAM_TX_UUID,
                                                NIMBLE_PROPERTY::NOTIFY);

  // Remote capture trigger
  pCaptureCmd = pService->createCharacteristic(CHAR_EYE_CAPTURE_RX_UUID,
                                               NIMBLE_PROPERTY::WRITE |
                                                   NIMBLE_PROPERTY::WRITE_NR);
  pCaptureCmd->setCallbacks(new CaptureCallback());

  pService->start();

  NimBLEAdvertising *pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(ICAN_EYE_SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->start();

  Serial.println("[BLE] iCan Eye service advertising.");
}

// ---------------------------------------------------------------------------
// Stream JPEG over BLE in chunks
// ---------------------------------------------------------------------------
void streamImageOverBle(const uint8_t *jpegData, size_t jpegLen) {
  if (!bleConnected) {
    Serial.println("[BLE] Not connected — skipping image stream.");
    return;
  }

  uint16_t totalChunks = (jpegLen + IMAGE_MAX_PAYLOAD - 1) / IMAGE_MAX_PAYLOAD;
  Serial.printf("[BLE] Streaming %u bytes in %u chunks.\n", jpegLen,
                totalChunks);

  uint8_t packet[IMAGE_MAX_PACKET_SIZE];

  for (uint16_t seq = 0; seq < totalChunks; seq++) {
    size_t offset = seq * IMAGE_MAX_PAYLOAD;
    size_t remaining = jpegLen - offset;
    size_t payloadLen =
        (remaining < IMAGE_MAX_PAYLOAD) ? remaining : IMAGE_MAX_PAYLOAD;

    // Header
    ImagePacketHeader hdr;
    hdr.sequence_number = seq;
    hdr.total_chunks = totalChunks;

    // Compute checksum over payload
    uint8_t xorChecksum = 0;
    for (size_t i = 0; i < payloadLen; i++) {
      xorChecksum ^= jpegData[offset + i];
    }
    hdr.checksum = xorChecksum;

    // Pack header + payload
    memcpy(packet, &hdr, IMAGE_HEADER_BYTES);
    memcpy(packet + IMAGE_HEADER_BYTES, jpegData + offset, payloadLen);

    pImageStream->setValue(packet, IMAGE_HEADER_BYTES + payloadLen);
    pImageStream->notify();

    // Small delay to avoid BLE congestion
    delay(5);
  }

  Serial.println("[BLE] Image stream complete.");
}

// ---------------------------------------------------------------------------
// Button debounce
// ---------------------------------------------------------------------------
static volatile unsigned long lastButtonPress = 0;
constexpr unsigned long DEBOUNCE_MS = 500;

void IRAM_ATTR buttonISR() {
  unsigned long now = millis();
  if (now - lastButtonPress > DEBOUNCE_MS) {
    lastButtonPress = now;
    captureRequest = true;
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("[iCan Eye] Booting...");

  // Button
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_BUTTON), buttonISR, FALLING);

  // Camera
  if (!initCamera()) {
    Serial.println("[iCan Eye] FATAL: Camera init failed. Halting.");
    while (true)
      delay(1000);
  }

  // BLE
  initBleEye();

  Serial.println("[iCan Eye] Ready. Press button to capture.");
}

// ---------------------------------------------------------------------------
// Main Loop
// ---------------------------------------------------------------------------
void loop() {
  if (!captureRequest) {
    delay(10);
    return;
  }
  captureRequest = false;

  Serial.println("[iCan Eye] Capturing image...");

  // Capture frame
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("[iCan Eye] ERROR: Frame buffer is null.");
    return;
  }

  Serial.printf("[iCan Eye] Captured %u bytes (JPEG, %ux%u).\n", fb->len,
                fb->width, fb->height);

  // --- Pipeline 1: Instant text (placeholder) ---
  // TODO (Task 2.2): Run SenseCraft AI / TFLite Micro model here
  const char *instantLabel = "object detected";
  if (bleConnected) {
    pInstantText->setValue(reinterpret_cast<const uint8_t *>(instantLabel),
                           strlen(instantLabel));
    pInstantText->notify();
    Serial.printf("[Pipeline 1] Sent instant text: \"%s\"\n", instantLabel);
  }

  // --- Pipeline 2: Stream JPEG to phone ---
  streamImageOverBle(fb->buf, fb->len);

  // Return frame buffer to driver
  esp_camera_fb_return(fb);
}
