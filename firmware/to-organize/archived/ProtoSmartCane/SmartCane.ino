#include "mux/mux.h"

#include "sensors/sensors.h"
#include "fusion/fusion.h"
#include "responses/responses.h"
#include "mode/mode.h"
#include "faults/faults.h"
#include "ble/ble.h"

void setup() {
    Serial.begin(115200);

    muxInit();
    setMode(NORMAL);

    initSensors();
    initActuators();
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

    checkFaults();
    fuseSituations();

    // MODE CONTROL
    if (currentSituation == FALL_DETECTED || faults.imu_fail)
        setMode(EMERGENCY);
    else if (currentSituation == OBJECT_NEAR || currentSituation == OBJECT_IMMINENT)
        setMode(HIGH_ALERT);
    else
        setMode(NORMAL);

    handleResponse();
    updateBLE();
}
