/*!
 * @file getAllData.ino
 * @brief This is a demo for retrieving all TOF data. Running this demo will allow you to get all TOF data.
 * @copyright  Copyright (c) 2010 DFRobot Co.Ltd (http://www.dfrobot.com)
 * @license     The MIT License (MIT)
 * @author [tangjie](jie.tang@dfrobot.com)
 * @version  V1.0
 * @date  2024-08-14
 * @url https://github.com/DFRobot/DFRobot_matrixLidarDistanceSensor
 */

#include "DFRobot_matrixLidarDistanceSensor.h"

DFRobot_matrixLidarDistanceSensor tof;
uint16_t buf[64];
char report[128];

void setup(void){
  Serial.begin(115200);
  while(tof.begin() != 0){
    Serial.println("begin error !!!!!");
  }
   Serial.println("begin success");
  //config matrix mode
  while(tof.getAllDataConfig(eMatrix_8X8) != 0){
    Serial.println("init error !!!!!");
    delay(1000);
  }
  Serial.println("init success");
}

void loop(void){
  tof.getAllData(buf);
  for (int i = 0; i < 64; i++) {
    snprintf(report, sizeof(report), "Zone : %3d, Distance : %4d mm\r\n",
                 i,
                 buf[i]);
    Serial.print(report);
  }
  Serial.println("------------------------------");
  delay(100);
}
