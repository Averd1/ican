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
    initialPacket.version = BLE_TELEMETRY_VERSION;
    initialPacket.batteryPercent = 100;
    initialPacket.currentMode = (uint8_t)NORMAL;
    telemetryCharacteristic->writeValue((uint8_t*)&initialPacket, sizeof(TelemetryPacket));

    BLE.advertise();

    if (DEBUG_MODE) Serial.println("BLE initialized and advertising");
}

void updateBLETelemetry() {
    TelemetryPacket packet = {};
    packet.version = BLE_TELEMETRY_VERSION;
    
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

    packet.imuAxCms2 = isnan(currentSensors.imu.ax) ? 0 : (int16_t)(currentSensors.imu.ax * 100.0f);
    packet.imuAyCms2 = isnan(currentSensors.imu.ay) ? 0 : (int16_t)(currentSensors.imu.ay * 100.0f);
    packet.imuAzCms2 = isnan(currentSensors.imu.az) ? 0 : (int16_t)(currentSensors.imu.az * 100.0f);
    packet.ultrasonicLeftMm = currentSensors.ultrasonicDistances[0];
    packet.ultrasonicRightMm = currentSensors.ultrasonicDistances[1];
    packet.matrixHeadMm = currentSensors.matrixSensorHeadDetected ?
                          currentSensors.matrixSensorHeadDistance :
                          SENSOR_ERROR_DISTANCE;
    packet.matrixWaistMm = currentSensors.matrixSensorWaistDetected ?
                           currentSensors.matrixSensorWaistDistance :
                           SENSOR_ERROR_DISTANCE;

    packet.healthFlags = 0;
    if (!systemFaults.imu_fail) packet.healthFlags |= HEALTH_IMU_OK;
    if (!systemFaults.ultrasonic_fail) packet.healthFlags |= HEALTH_ULTRASONIC_OK;
    if (!systemFaults.matrixSensor_fail) packet.healthFlags |= HEALTH_MATRIX_SENSOR_OK;
#if !ISOLATED_SENSOR_TEST_MODE
    if (!systemFaults.heart_fail) packet.healthFlags |= HEALTH_PULSE_OK;
#endif
    if (!systemFaults.mux_fail) packet.healthFlags |= HEALTH_MUX_OK;
    packet.healthFlags |= hapticDriverHealthFlags();

    if (DEBUG_MODE) {
        Serial.print("BLE_TX flags=0x");
        if (packet.flags < 0x10) Serial.print("0");
        Serial.print(packet.flags, HEX);
        Serial.print(" fall=");
        Serial.print((packet.flags & 0x01) ? 1 : 0);
        Serial.print(" stress=");
        Serial.print((packet.flags & 0x02) ? 1 : 0);
        Serial.print(" near=");
        Serial.print((packet.flags & 0x04) ? 1 : 0);
        Serial.print(" imminent=");
        Serial.print((packet.flags & 0x08) ? 1 : 0);
        Serial.print(" health=0x");
        if (packet.healthFlags < 0x1000) Serial.print("0");
        if (packet.healthFlags < 0x0100) Serial.print("0");
        if (packet.healthFlags < 0x0010) Serial.print("0");
        Serial.println(packet.healthFlags, HEX);
    }
    
    if (telemetryCharacteristic) {
        telemetryCharacteristic->writeValue((uint8_t*)&packet, sizeof(TelemetryPacket));
    }
    
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
