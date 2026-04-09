#include "ble.h"
#include "../sensors/imu.h"
#include "../sensors/ultrasonic.h"
#include "../sensors/light.h"
#include "../sensors/heart.h"
#include "../mode/mode.h"
#include "../fusion/fusion.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

BLECharacteristic *c;

void initBLE() {

    BLEDevice::init("SmartCane");

    BLEServer *s = BLEDevice::createServer();
    BLEService *svc = s->createService("12345678-1234");

    c = svc->createCharacteristic(
        "abcd1234",
        BLECharacteristic::PROPERTY_NOTIFY
    );

    svc->start();
    BLEDevice::getAdvertising()->start();
}

void updateBLE() {

    static unsigned long t = 0;
    if (millis() - t < 200) return;
    t = millis();

    String data =
        String(imu.ax)+","+String(imu.ay)+","+String(imu.az)+","+
        String(dist_left)+","+String(dist_right)+","+
        String(lux)+","+String(heart_raw)+","+
        String(currentMode)+","+
        String(currentSituation);

    c->setValue(data.c_str());
    c->notify();

    Serial.println(data);
}
