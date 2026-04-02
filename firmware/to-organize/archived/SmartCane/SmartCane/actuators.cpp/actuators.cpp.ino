#include "actuators.h"
#include "mux.h"
#include <Wire.h>

#define DRV_ADDR 0x5A

#define LEFT_CHANNEL 2
#define RIGHT_CHANNEL 3

#define BUZZER_PIN 9
#define LED_PIN 6

void writeDRV(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(DRV_ADDR);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

void initActuators() {
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(LED_PIN, OUTPUT);

    selectMux(LEFT_CHANNEL);
    writeDRV(0x01, 0x00);

    selectMux(RIGHT_CHANNEL);
    writeDRV(0x01, 0x00);
}

void vibrateLeft(uint8_t strength) {
    selectMux(LEFT_CHANNEL);
    writeDRV(0x04, strength);
}

void vibrateRight(uint8_t strength) {
    selectMux(RIGHT_CHANNEL);
    writeDRV(0x04, strength);
}

void buzzerOn() {
    digitalWrite(BUZZER_PIN, HIGH);
}

void buzzerOff() {
    digitalWrite(BUZZER_PIN, LOW);
}

void setLED(int brightness) {
    analogWrite(LED_PIN, brightness);
}
