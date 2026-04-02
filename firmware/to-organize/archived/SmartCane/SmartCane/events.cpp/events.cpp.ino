#include "events.h"
#include "sensors.h"

Events events;

void detectEvents() {

    events.low_light = (sensor.light_level < 200);

    events.obstacle_left = (sensor.dist_left < 100);
    events.obstacle_right = (sensor.dist_right < 100);

    events.heart_abnormal = (sensor.heart_bpm > 140 || sensor.heart_bpm < 40);
}
