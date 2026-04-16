/*
 * BLE Communication Module
 * Handles telemetry transmission to mobile app
 */

#include "ble.h"
#include <Arduino.h>
#include <ArduinoBLE.h>

// BLE service and characteristic
BLEService caneService(BLE_SERVICE_UUID);
BLECharacteristic telemetryCharacteristic(BLE_CHARACTERISTIC_UUID, BLERead | BLENotify, sizeof(TelemetryPacket));

void bleInit() {
    if (!BLE.begin()) {
        if (DEBUG_MODE) Serial.println("BLE initialization failed!");
        return;
    }

    BLE.setLocalName(BLE_DEVICE_NAME);
    BLE.setAdvertisedService(caneService);

    caneService.addCharacteristic(telemetryCharacteristic);
    BLE.addService(caneService);

    // Initialize telemetry packet
    TelemetryPacket initialPacket = {BLE_TELEMETRY_VERSION, 100, (uint8_t)NORMAL, 0, 0};
    telemetryCharacteristic.writeValue((uint8_t*)&initialPacket, sizeof(TelemetryPacket));

    BLE.advertise();

    if (DEBUG_MODE) Serial.println("BLE initialized and advertising");
}

void updateBLETelemetry() {
    // OPTIMIZED Telemetry packet (v2)
    // Minimal data sent to reduce BLE power consumption
    // App calculates battery lifetime using power profile lookup table
    
    TelemetryPacket packet;
    packet.version = BLE_TELEMETRY_VERSION;  // v2
    
    // Primary: Battery percentage (app uses this to estimate runtime)
    packet.batteryPercent = (uint8_t)currentSensors.batteryLevel;
    
    // Secondary: Current mode (app looks up power draw for this mode)
    // NORMAL=0, LOW_POWER=1, HIGH_STRESS=2, EMERGENCY=3
    packet.currentMode = (uint8_t)currentMode;
    
    // Health info: Heart rate
    packet.heartBPM = (currentSensors.heartBPM > 255) ? 255 : (uint8_t)currentSensors.heartBPM;
    
    // Status flags
    packet.flags = 0;
    if (currentSituation == FALL_DETECTED) packet.flags |= 0x01;
    if (currentSituation == HIGH_STRESS_EVENT) packet.flags |= 0x02;
    if (obstacleNear) packet.flags |= 0x04;
    if (obstacleImminent) packet.flags |= 0x08;
    
    // Send the simplified packet
    telemetryCharacteristic.writeValue((uint8_t*)&packet, sizeof(TelemetryPacket));
    
    if (DEBUG_MODE && telemetrySequence++ % 50 == 0) {
        Serial.print("BLE: ");
        Serial.print(packet.batteryPercent); Serial.print("% | Mode: ");
        Serial.print(packet.currentMode); Serial.print(" | HR: ");
        Serial.println(packet.heartBPM);
    }
}

void blePoll() {
    BLE.poll();
}
