#include "heart.h"

#define HEART_PIN A0

int heart_raw = 0;

void initHeart() {
    pinMode(HEART_PIN, INPUT);
}

void updateHeart() {
    heart_raw = analogRead(HEART_PIN);
}
