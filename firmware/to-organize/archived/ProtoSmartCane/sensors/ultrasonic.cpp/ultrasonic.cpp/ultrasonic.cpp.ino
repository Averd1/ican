#include "ultrasonic.h"

#define L_TRIG 5
#define L_ECHO 3
#define R_TRIG 6
#define R_ECHO 4

int dist_left = 0;
int dist_right = 0;

int readUS(int trig, int echo) {
    digitalWrite(trig, LOW);
    delayMicroseconds(2);
    digitalWrite(trig, HIGH);
    delayMicroseconds(10);
    digitalWrite(trig, LOW);

    long duration = pulseIn(echo, HIGH, 30000);
    if (duration == 0) return -1;
    return duration / 58;
}

void initUltrasonic() {
    pinMode(L_TRIG, OUTPUT);
    pinMode(L_ECHO, INPUT);
    pinMode(R_TRIG, OUTPUT);
    pinMode(R_ECHO, INPUT);
}

void updateUltrasonic() {
    dist_left = readUS(L_TRIG, L_ECHO);
    dist_right = readUS(R_TRIG, R_ECHO);
}
