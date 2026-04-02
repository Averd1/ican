#pragma once

struct FaultState{
  bool imu_fail;
  bool ultrasonic_fail;
  bool light_fail;
  bool heart_fail;
};

extern FaultState faults;

void checkFaults();
