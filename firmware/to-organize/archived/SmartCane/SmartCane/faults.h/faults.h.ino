#pragma once 

struct Faults{
  bool heart_fail;
};

extern Faults faults;

void detectFaults();
