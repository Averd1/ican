#include <Arduino.h>
#include "logging.h"
#include "sensors.h"
#include "state.h"

unsigned long lastLog = 0;

void logSystem() {

    if (millis() - lastLog < 200) return;
    lastLog = millis();

    Serial.print("HR: ");
    Serial.print(sensor.heart_bpm);

    Serial.print(" | Light: ");
    Serial.print(sensor.light_level);

    Serial.print(" | Mode: ");
    Serial.print(currentMode);

    Serial.println();
}
