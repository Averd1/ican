#pragma once

struct Events {
    bool low_light;
    bool obstacle_left;
    bool obstacle_right;
    bool heart_abnormal;
};

extern Events events;

void detectEvents();
