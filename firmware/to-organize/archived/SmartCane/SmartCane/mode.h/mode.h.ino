#pragma once

enum Mode {
    NORMAL,
    LOW_POWER,
    HIGH_ALERT,
    EMERGENCY
};

struct ModeConfig {
    int imuInterval;
    int ultrasonicInterval;
};

extern Mode currentMode;
extern ModeConfig config;

void setMode(Mode m);
