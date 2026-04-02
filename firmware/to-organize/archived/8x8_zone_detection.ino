#include <Wire.h>
#include "DFRobot_matrixLidarDistanceSensor.h"

TwoWire I2C_2 = TwoWire(1);
DFRobot_matrixLidarDistanceSensor tof(0x33, &I2C_2);

#define SDA_2 D6
#define SCL_2 D7

#define DIST_THRESHOLD 800  // mm (adjust as needed)

uint16_t buf[64];

void setup(void){
  Serial.begin(115200);

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

  bool topDetected = false;
  bool bottomDetected = false;
  bool leftDetected = false;
  bool middleDetected = false;
  bool rightDetected = false;

  for (int i = 0; i < 64; i++) {

    uint16_t d = buf[i];

    // Ignore invalid / far readings
    if (d == 0 || d > DIST_THRESHOLD) continue;

    int row = i / 8;
    int col = i % 8;

    // Vertical zones
    if (row < 4) topDetected = true;
    else bottomDetected = true;

    // Horizontal zones
    if (col <= 2) leftDetected = true;
    else if (col <= 4) middleDetected = true;
    else rightDetected = true;
  }

  // ───── PRINT RESULTS ─────
  Serial.print("Zones → ");

  if (topDetected) Serial.print("TOP ");
  if (bottomDetected) Serial.print("BOTTOM ");
  if (leftDetected) Serial.print("LEFT ");
  if (middleDetected) Serial.print("MIDDLE ");
  if (rightDetected) Serial.print("RIGHT ");

  Serial.println();

  delay(100);
}