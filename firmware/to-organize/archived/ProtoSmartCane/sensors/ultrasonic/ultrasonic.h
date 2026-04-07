#pragma once

#include <Arduino.h>
#include "../../mux/mux.h"

// URM37 Ultrasonic I2C addresses and registers
#define ULTRASONIC_I2C_ADDR 0x11
#define ULTRASONIC_DIST_LOW 0x01
#define ULTRASONIC_DIST_HIGH 0x02
#define ULTRASONIC_TRIGGER 0x04

// Ultrasonic detection thresholds (mm)
#define ULTRASONIC_NEAR 800
#define ULTRASONIC_IMMINENT 400

// Support for 2 ultrasonic sensors
#define NUM_ULTRASONIC 2

extern bool ultrasonicNear;
extern bool ultrasonicImminent;
extern uint16_t ultrasonicDistances[NUM_ULTRASONIC];

void initUltrasonic();
void updateUltrasonicData();
uint16_t readUltrasonicDistance(uint8_t sensorIndex);