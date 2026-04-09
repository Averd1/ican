/*!
 * @file getObstacleDistance.ino
 * @brief This is a demo to retrieve the distance to an obstacle using the TOF sensor. Running this demo will print the distance to the obstacle.
 * @copyright  Copyright (c) 2010 DFRobot Co.Ltd (http://www.dfrobot.com)
 * @license     The MIT License (MIT)
 * @author [tangjie](jie.tang@dfrobot.com)
 * @version  V1.0
 * @date  2024-08-14
 * @url https://github.com/DFRobot/DFRobot_matrixLidarDistanceSensor
 */

#include "DFRobot_matrixLidarDistanceSensor.h"

DFRobot_matrixLidarDistanceSensor tof;
void setup(void){
  Serial.begin(115200);
  while(tof.begin() != 0){
    Serial.println("begin error !!!!!");
  }
  Serial.println("begin success");
  //When using obstacle avoidance, the matrix can only be set to 4*4
  while(tof.getAllDataConfig(eMatrix_4x4) != 0){
    Serial.println("init error !!!!!");
    delay(1000);
  }
 // Set the obstacle avoidance distance to 15 centimeters
  while(tof.configAvoidance(15) != 0){
    Serial.println("init avoid error !!!!!");
    delay(1000);
  }
  Serial.println("init success");
}

void loop(void){
  tof.requestObstacleDistance();
  uint16_t L = tof.getDistance(eLeft);
  uint16_t M = tof.getDistance(eMiddle);
  uint16_t R = tof.getDistance(eRight);
  Serial.print("L: ");
  Serial.print(L);
  Serial.print(" ,M: ");
  Serial.print(M);
  Serial.print(" ,R: ");
  Serial.print(R);
  
  Serial.println("------------------------------");
  delay(100);
}
