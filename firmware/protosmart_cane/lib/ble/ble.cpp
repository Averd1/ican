/*
 * BLE Communication Module
 * Handles telemetry transmission to mobile app
 */

#include "ble.h"
#include <Arduino.h>
#include <ArduinoBLE.h>
#include "../actuators/haptic_driver.h"

// BLE objects are constructed lazily inside bleInit() to avoid
// ArduinoBLE static constructors running before setup() (causes boot panic)
static BLEService* caneService = nullptr;
static BLECharacteristic* telemetryCharacteristic = nullptr;

void bleInit() {
    // Construct BLE objects here, not at global static init time
    caneService = new BLEService(BLE_SERVICE_UUID);
    telemetryCharacteristic = new BLECharacteristic(BLE_CHARACTERISTIC_UUID, BLERead | BLENotify, sizeof(TelemetryPacket));

    if (!BLE.begin()) {
        if (DEBUG_MODE) Serial.println("BLE initialization failed!");
        return;
    }

    BLE.setLocalName(BLE_DEVICE_NAME);
    BLE.setAdvertisedService(*caneService);

    caneService->addCharacteristic(*telemetryCharacteristic);
    BLE.addService(*caneService);

    // Initialize telemetry packet
    TelemetryPacket initialPacket = {};
    initialPacket.batteryPercent = 100;
    telemetryCharacteristic->writeValue((uint8_t*)&initialPacket, sizeof(TelemetryPacket));

    BLE.advertise();

    if (DEBUG_MODE) Serial.println("BLE initialized and advertising");
}

void updateBLETelemetry() {
    TelemetryPacket packet = {};

    // App-compatible status flags:
    // bit0 = fall detected, bit1 = pulse valid.
    packet.flags = 0;
    if (currentSituation == FALL_DETECTED) packet.flags |= 0x01;
    if (currentSensors.pulseDetected) packet.flags |= 0x02;

    packet.heartBPM = (currentSensors.heartBPM > 255) ? 255 : (uint8_t)currentSensors.heartBPM;
    packet.batteryPercent = (uint8_t)currentSensors.batteryLevel;
    packet.yawAngleTenths = 0;
    packet.reserved = 0;

    uint16_t healthFlags = 0;
    if (!systemFaults.imu_fail) healthFlags |= HEALTH_IMU_OK;
    if (!systemFaults.ultrasonic_fail) healthFlags |= HEALTH_ULTRASONIC_OK;
    if (!systemFaults.matrixSensor_fail) healthFlags |= HEALTH_MATRIX_SENSOR_OK;
#if !ISOLATED_SENSOR_TEST_MODE
    if (!systemFaults.heart_fail) healthFlags |= HEALTH_PULSE_OK;
#endif
    if (!systemFaults.mux_fail) healthFlags |= HEALTH_MUX_OK;
    healthFlags |= hapticDriverHealthFlags();

    if (DEBUG_MODE) {
        Serial.print("BLE_TX flags=0x");
        if (packet.flags < 0x10) Serial.print("0");
        Serial.print(packet.flags, HEX);
        Serial.print(" fall=");
        Serial.print((packet.flags & 0x01) ? 1 : 0);
        Serial.print(" pulseValid=");
        Serial.print((packet.flags & 0x02) ? 1 : 0);
        Serial.print(" bpm=");
        Serial.print(packet.heartBPM);
        Serial.print(" battery=");
        Serial.print(packet.batteryPercent);
        Serial.print(" health=0x");
        if (healthFlags < 0x1000) Serial.print("0");
        if (healthFlags < 0x0100) Serial.print("0");
        if (healthFlags < 0x0010) Serial.print("0");
        Serial.println(healthFlags, HEX);
    }
    
    if (telemetryCharacteristic) {
        telemetryCharacteristic->writeValue((uint8_t*)&packet, sizeof(TelemetryPacket));
    }
    
    if (DEBUG_MODE && telemetrySequence++ % 50 == 0) {
        Serial.print("BLE: ");
        Serial.print(packet.batteryPercent); Serial.print("% | Mode: ");
        Serial.print((uint8_t)currentMode); Serial.print(" | HR: ");
        Serial.println(packet.heartBPM);
    }
}

void blePoll() {
    BLE.poll();
}
