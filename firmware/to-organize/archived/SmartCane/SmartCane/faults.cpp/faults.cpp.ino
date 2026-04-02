#include "faults.h"
#include "sensors.h"

faults faults; 

void detectFaults(){
  faults.heart_fail = (sensor.heart_raw == 0);
}
