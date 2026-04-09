#include <Wire.h>
#include "DFRobot_matrixLidarDistanceSensor.h"

TwoWire I2C_2 = TwoWire(1);
DFRobot_matrixLidarDistanceSensor tof(0x33, &I2C_2);

#define SDA_2 D6
#define SCL_2 D7

#define DIST_THRESHOLD 1500  // mm
#define MIN_DIST 400         // 40 cm → max blinking starts here

// LED pins
#define LED_TOP D4
#define LED_LEFT D2
#define LED_RIGHT D3

uint16_t buf[64];

// Blink timing
unsigned long previousMillis = 0;
bool ledState = false;

void setup(void){
  Serial.begin(115200);

  pinMode(LED_TOP, OUTPUT);
  pinMode(LED_LEFT, OUTPUT);
  pinMode(LED_RIGHT, OUTPUT);

  I2C_2.begin(SDA_2, SCL_2);

  while(tof.begin() != 0){
    Serial.println("begin error !!!!!");
    delay(1000);
  }
  Serial.println("begin success");

  while(tof.getAllDataConfig(eMatrix_8X8) != 0){
    Serial.println("init error !!!!!");
    delay(1000);
  }
  Serial.println("8x8 init success");
}

void loop(void){

  tof.getAllData(buf);

  bool headDetected = false;
  bool waistFrontDetected = false;

  uint16_t closestHead = 9999;
  uint16_t closestWaist = 9999;

  for (int i = 0; i < 64; i++) {

    uint16_t d = buf[i];

    if (d == 0 || d > DIST_THRESHOLD) continue;

    int row = i / 8;
    int col = i % 8;

    // ───── HEAD (top 4 rows) ─────
    if (row < 4) {
      headDetected = true;
      if (d < closestHead) closestHead = d;
    }

    // ───── WAIST FRONT (bottom 4 rows + middle 6 columns) ─────
    if (row >= 4 && col >= 1 && col <= 6) {
      waistFrontDetected = true;
      if (d < closestWaist) closestWaist = d;
    }
  }

  // ───── BLINK SPEED CALCULATION ─────
  int headInterval = 1000;
  int waistInterval = 1000;

  if (headDetected) {
    uint16_t d = (closestHead < MIN_DIST) ? MIN_DIST : closestHead;
    headInterval = map(d, MIN_DIST, DIST_THRESHOLD, 50, 500);
    headInterval = constrain(headInterval, 50, 500);
  }

  if (waistFrontDetected) {
    uint16_t d = (closestWaist < MIN_DIST) ? MIN_DIST : closestWaist;
    waistInterval = map(d, MIN_DIST, DIST_THRESHOLD, 50, 500);
    waistInterval = constrain(waistInterval, 50, 500);
  }

  unsigned long currentMillis = millis();

  // ───── HEAD LED (D4) ─────
  if (headDetected) {
    if (currentMillis - previousMillis >= headInterval) {
      previousMillis = currentMillis;
      ledState = !ledState;
      digitalWrite(LED_TOP, ledState);
    }
  } else {
    digitalWrite(LED_TOP, LOW);
  }

  // ───── WAIST LEDS (D2 + D3) ─────
  if (waistFrontDetected) {
    if (currentMillis - previousMillis >= waistInterval) {
      previousMillis = currentMillis;
      ledState = !ledState;
      digitalWrite(LED_LEFT, ledState);
      digitalWrite(LED_RIGHT, ledState);
    }
  } else {
    digitalWrite(LED_LEFT, LOW);
    digitalWrite(LED_RIGHT, LOW);
  }

  delay(30);
}