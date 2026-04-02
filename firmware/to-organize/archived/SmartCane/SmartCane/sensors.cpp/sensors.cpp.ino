#include "sensors.h"
#include "mux.h"
#include <Wire.h>
#include <Adafruit_VEML7700.h>

#define URM_L_TRIG 5
#define URM_L_ECHO 3

#define URM_R_TRIG 6
#define URM_R_ECHO 4

#define HEART_PIN A0
#define LIGHT_CHANNEL 1

Adafruit_VEML7700 veml;

SensorData sensor;

// simple filtering buffers
float luxFiltered = 0;
int distLFiltered = 0;
int distRFiltered = 0;

int readURM(int trig, int echo) {
    digitalWrite(trig, LOW);
    digitalWrite(trig, HIGH);

    long duration = pulseIn(echo, LOW);
    if (duration == 0) return -1;

    return duration / 50;
}

void initSensors() {

    pinMode(URM_L_TRIG, OUTPUT);
    pinMode(URM_L_ECHO, INPUT);

    pinMode(URM_R_TRIG, OUTPUT);
    pinMode(URM_R_ECHO, INPUT);

    pinMode(HEART_PIN, INPUT);

    selectMux(LIGHT_CHANNEL);

    veml.begin();
}

void updateSensors() {

    int rawL = readURM(URM_L_TRIG, URM_L_ECHO);
    int rawR = readURM(URM_R_TRIG, URM_R_ECHO);

    selectMux(LIGHT_CHANNEL);
    float rawLux = veml.readLux();

    int rawHeart = analogRead(HEART_PIN);

    // LOW PASS FILTER
    distLFiltered = 0.7 * distLFiltered + 0.3 * rawL;
    distRFiltered = 0.7 * distRFiltered + 0.3 * rawR;
    luxFiltered   = 0.7 * luxFiltered   + 0.3 * rawLux;

    sensor.dist_left = distLFiltered;
    sensor.dist_right = distRFiltered;
    sensor.lux = luxFiltered;
    sensor.heart_raw = rawHeart;
}
