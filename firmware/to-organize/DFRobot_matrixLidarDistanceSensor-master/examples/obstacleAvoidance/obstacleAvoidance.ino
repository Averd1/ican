/*!
 * @file obstacleAvoidance.ino
 * @brief This is a basic obstacle avoidance demo. Running this demo will perform basic obstacle avoidance.
 * @copyright  Copyright (c) 2010 DFRobot Co.Ltd (http://www.dfrobot.com)
 * @license     The MIT License (MIT)
 * @author [tangjie](jie.tang@dfrobot.com)
 * @version  V1.0
 * @date  2024-08-14
 * @url https://github.com/DFRobot/DFRobot_matrixLidarDistanceSensor
 */

#include "DFRobot_matrixLidarDistanceSensor.h"

DFRobot_matrixLidarDistanceSensor tof;
uint16_t buf[2];


#define L_M  1
#define R_M  2
#define CW   0
#define CCW  1

uint8_t nowDirection = 0;

#define FORWARD  3
#define LEFT  1
#define RIGHT  2

void motor(uint8_t speed, uint8_t dir, uint8_t mt){
    Wire.beginTransmission(0x10);
    if(mt == L_M){
        Wire.write((uint8_t)0);
        Wire.write(dir);
        Wire.write(speed);
    }else if(mt == R_M){
        Wire.write((uint8_t)2);
        Wire.write(dir);
        Wire.write(speed);
    }
    Wire.endTransmission();
}

// Move forward
void moveForward() {
  motor(60, CW, L_M);
  motor(60, CW, R_M);
  
}

// Move backward
void moveBackward() {
 
  motor(40, CCW, L_M);
  motor(40, CCW, R_M);
 
}

// Turn left
void turnLeft() {
  motor(40, CCW, L_M);
  motor(40, CW, R_M);
}

// Turn right
void turnRight() {
  motor(40, CW, L_M);
  motor(40, CCW, R_M);
 
}

// Difference in wheel speeds between left and right
// Turn left
void turnLeft1(uint8_t speed) {
  motor(20, CW, L_M);
  motor(120, CW, R_M);
}

// Turn right
void turnRight1(uint8_t speed) {
  motor(120, CW, L_M);
  motor(20, CW, R_M);
 
}


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
  // Get and return obstacle avoidance suggestions
  tof.requestObstacleSensorData();
  uint8_t dir = tof.getDir();
  uint8_t urgency = tof.getEmergencyFlag();
  switch(dir){
    case FORWARD:
      moveForward();
      break;
    case RIGHT:
      if(urgency > 0){
        turnRight1(buf[1]);
      }else{
        turnRight();
      }
      break;
    case LEFT:
      if(urgency > 0){
        turnLeft1(buf[1]);
      }else{
        turnLeft();
      }
      break;
    default:
      break;
  }
  delay(1);
}
