/*
 * BLE Communication Module
 * Handles telemetry transmission to mobile app
 */

#include "ble.h"
#include <Arduino.h>
#include <ArduinoBLE.h>
#include <math.h>

// BLE objects are constructed lazily inside bleInit() to avoid
// ArduinoBLE static constructors running before setup() (causes boot panic)
static BLEService* caneService = nullptr;
static BLECharacteristic* telemetryCharacteristic = nullptr;

static int16_t encodeAccel(float value) {
    if (isnan(value)) {
        return INT16_MIN;
    }
    return (int16_t)constrain((long)lroundf(value * 100.0f), -32767L, 32767L);
}

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
    TelemetryPacket initialPacket = {
        BLE_TELEMETRY_VERSION,
        100,
        (uint8_t)NORMAL,
        0,
        0,
        0,
        0,
        0,
        0,
        SENSOR_ERROR_DISTANCE,
        SENSOR_ERROR_DISTANCE,
        SENSOR_ERROR_DISTANCE,
        SENSOR_ERROR_DISTANCE,
        0,
    };
    telemetryCharacteristic->writeValue((uint8_t*)&initialPacket, sizeof(TelemetryPacket));

    BLE.advertise();

    if (DEBUG_MODE) Serial.println("BLE initialized and advertising");
}

void updateBLETelemetry() {
    // v4 telemetry packet: battery/mode/flags + validity bits + IMU + pulse + distances
    
    TelemetryPacket packet;
    packet.version = BLE_TELEMETRY_VERSION;  // v4
    
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

    packet.sensorStatus = 0;
    
    bool imuValid = !systemFaults.imu_fail &&
        !isnan(currentSensors.imu.ax) && !isnan(currentSensors.imu.ay) && !isnan(currentSensors.imu.az);
    if (imuValid) packet.sensorStatus |= 0x01;
    packet.imuAxCms2 = encodeAccel(currentSensors.imu.ax);
    packet.imuAyCms2 = encodeAccel(currentSensors.imu.ay);
    packet.imuAzCms2 = encodeAccel(currentSensors.imu.az);

    // Distances in mm
    packet.ultrasonicLeftMm = currentSensors.ultrasonicDistances[0];
    packet.ultrasonicRightMm = currentSensors.ultrasonicDistances[1];
    packet.matrixHeadMm = currentSensors.matrixSensorHeadDetected ?
        currentSensors.matrixSensorHeadDistance : SENSOR_ERROR_DISTANCE;
    packet.matrixWaistMm = currentSensors.matrixSensorWaistDetected ?
        currentSensors.matrixSensorWaistDistance : SENSOR_ERROR_DISTANCE;
    packet.heartRaw = (uint16_t)max(currentSensors.heartRaw, 0);

    if (packet.ultrasonicLeftMm != SENSOR_ERROR_DISTANCE) packet.sensorStatus |= 0x02;
    if (packet.ultrasonicRightMm != SENSOR_ERROR_DISTANCE) packet.sensorStatus |= 0x04;
    if (packet.matrixHeadMm != SENSOR_ERROR_DISTANCE) packet.sensorStatus |= 0x08;
    if (packet.matrixWaistMm != SENSOR_ERROR_DISTANCE) packet.sensorStatus |= 0x10;
    if (!systemFaults.heart_fail) packet.sensorStatus |= 0x20;
    packet.sensorStatus |= 0x40;

    // Send packet
    if (telemetryCharacteristic) {
        telemetryCharacteristic->writeValue((uint8_t*)&packet, sizeof(TelemetryPacket));
    }
    
    if (DEBUG_MODE && telemetrySequence++ % 50 == 0) {
        Serial.print("BLE: ");
        Serial.print(packet.batteryPercent); Serial.print("% | Mode: ");
        Serial.print(packet.currentMode); Serial.print(" | HR: ");
        Serial.print(packet.heartBPM); Serial.print(" raw=");
        Serial.print(packet.heartRaw); Serial.print(" | UL/LR: ");
        Serial.print(packet.ultrasonicLeftMm); Serial.print("/");
        Serial.print(packet.ultrasonicRightMm); Serial.print(" | 8x8 H/W: ");
        Serial.print(packet.matrixHeadMm); Serial.print("/");
        Serial.println(packet.matrixWaistMm);
    }
}

void blePoll() {
    BLE.poll();
}
