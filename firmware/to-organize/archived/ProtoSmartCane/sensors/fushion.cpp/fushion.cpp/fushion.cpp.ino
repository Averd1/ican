#include "fusion.h"
#include "../imu/imu.h"
#include "../ultrasonic/ultrasonic.h"
#include "../lidar/lidar.h"
#include "../pulse/pulse.h"

Situation currentSituation = NONE;

void fuseSituations() {
    // Calculate IMU acceleration magnitude for fall detection
    float accelMag = sqrt(
        imu.ax * imu.ax +
        imu.ay * imu.ay +
        imu.az * imu.az
    );

    // Get minimum distance from ultrasonic sensors
    uint16_t minUltrasonicDist = 9999;
    for (int i = 0; i < NUM_ULTRASONIC; i++) {
        if (ultrasonicDistances[i] > 0 && ultrasonicDistances[i] < minUltrasonicDist) {
            minUltrasonicDist = ultrasonicDistances[i];
        }
    }

    // PRIORITY 1: FALL DETECTION (highest priority - triggers emergency mode)
    if (accelMag > 25.0) {
        currentSituation = FALL_DETECTED;
        return;
    }

    // PRIORITY 2: HIGH STRESS (close obstacle + abnormal heart rate)
    if ((minUltrasonicDist < 300 || obstacleImminent) && heartAbnormal) {
        currentSituation = HIGH_STRESS;
        return;
    }

    // PRIORITY 3: OBSTACLE DETECTION HIERARCHY
    if (obstacleImminent || (minUltrasonicDist > 0 && minUltrasonicDist < 200)) {
        currentSituation = OBJECT_IMMINENT;
    } else if (obstacleNear || ultrasonicNear || (minUltrasonicDist > 0 && minUltrasonicDist < 500)) {
        currentSituation = OBJECT_NEAR;
    } else if (minUltrasonicDist > 0 && minUltrasonicDist < 1000) {
        currentSituation = OBJECT_FAR;
    } else {
        currentSituation = NONE;
    }

    // Note: LOW_LIGHT detection removed as light sensor not implemented in current structure
}
