#include "responses.h"
#include "../sensors/sensors.h"
#include "../fusion/fusion.h"

#define BUZZER 9
#define LED 6

unsigned long lastBuzz = 0;
bool state = false;

void initActuators() {
    pinMode(BUZZER, OUTPUT);
    pinMode(LED, OUTPUT);
}

void setLED(int val) {
    analogWrite(LED, val);
}

void buzzerPulse(int speed) {
    if (millis() - lastBuzz > speed) {
        state = !state;
        digitalWrite(BUZZER, state);
        lastBuzz = millis();
    }
}

void buzzerOff() {
    digitalWrite(BUZZER, LOW);
}

void handleResponse() {

    switch(currentSituation) {

        case OBJECT_FAR:
            buzzerPulse(300);
            setLED(100);
            break;

        case OBJECT_NEAR:
            buzzerPulse(150);
            setLED(180);
            break;

        case OBJECT_IMMINENT:
            buzzerPulse(50);
            setLED(255);
            break;

        case FALL_DETECTED:
            buzzerPulse(20);
            setLED(255);
            break;

        case LOW_LIGHT:
            buzzerOff();
            setLED(255);
            break;

        default:
            buzzerOff();
            setLED(0);
            break;
    }
  
}

void handleFallResponse(){
  serial.println(" !!! FALL DETECTED !!!");
}
