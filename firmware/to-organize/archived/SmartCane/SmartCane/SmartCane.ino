#include "mux.h"
#include "mode.h"
#include "imu.h"
#include "sensors.h"
#include "actuators.h"
#include "logic.h"
#include "ble.h"

void setup() {
    Serial.begin(115200);

    muxInit();
    setMode(NORMAL);

    initSensors();
    initActuators();
    initIMU();
    initBLE();

    Serial.println("SYSTEM READY");
}

void loop() {

    static unsigned long lastIMU = 0;
    static unsigned long lastSensors = 0;

    unsigned long now = millis();

    if (now - lastIMU > config.imuInterval) {
        updateIMU();
        lastIMU = now;
    }

    if (now - lastSensors > config.ultrasonicInterval) {
        updateSensors();
        lastSensors = now;
    }

    runLogic();
    updateBLE();
}
