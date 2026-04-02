#include "ble.h"
#include "sensors.h"
#include "imu.h"
#include "mode.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

BLECharacteristic *imuCharacteristic;

#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "abcd1234-ab12-cd34-ef56-1234567890ab"

void initBLE() {

    BLEDevice::init("SmartCane");

    BLEServer *server = BLEDevice::createServer();
    BLEService *service = server->createService(SERVICE_UUID);

    imuCharacteristic = service->createCharacteristic(
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );

    imuCharacteristic->addDescriptor(new BLE2902());

    service->start();

    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->start();

    Serial.println("BLE READY");
}

void updateBLE() {

    static unsigned long lastBLE = 0;

    if (millis() - lastBLE < 200) return;  // 5 Hz
    lastBLE = millis();

    String payload =
        String("AX:") + imu.ax +
        ",AY:" + imu.ay +
        ",AZ:" + imu.az +
        ",L:" + sensor.dist_left +
        ",R:" + sensor.dist_right +
        ",Lux:" + sensor.lux +
        ",HR:" + sensor.heart_raw +
        ",Mode:" + currentMode;

    imuCharacteristic->setValue(payload.c_str());
    imuCharacteristic->notify();
}
