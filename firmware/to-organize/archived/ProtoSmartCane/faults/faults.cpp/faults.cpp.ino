#include "faults.h"
#include "../sensors/imu.h"
#include "../sensors/ultrasonic.h"
#include "../sensors/light.h"

FaultState faults;

void checkFaults() {

    faults.imu_fail = (imu.ax == 0 && imu.ay == 0 && imu.az == 0);

    faults.ultrasonic_fail = (dist_left == -1 && dist_right == -1);

    faults.light_fail = (lux < 0);

    faults.heart_fail = false;
}
