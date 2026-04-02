#include "fusion.h"
#include "../sensors/imu.h"
#include "../sensors/ultrasonic.h"
#include "../sensors/light.h"
#include "../sensors/heart.h"

Situation currentSituation = NONE;

void fuseSituations() {

    float mag = sqrt(
        imu.ax * imu.ax +
        imu.ay * imu.ay +
        imu.az * imu.az
    );

    int dist = min(dist_left, dist_right);

    if (mag > 25.0) {
        currentSituation = FALL_DETECTED;
        return;
    }

    if (dist < 30 && heart_raw > 600) {
        currentSituation = HIGH_STRESS;
        return;
    }

    if (dist > 0 && dist < 10)
        currentSituation = OBJECT_IMMINENT;
    else if (dist < 30)
        currentSituation = OBJECT_NEAR;
    else if (dist < 60)
        currentSituation = OBJECT_FAR;
    else if (lux < 20)
        currentSituation = LOW_LIGHT;
    else
        currentSituation = NONE;
}
