#include "mode.h"

Mode currentMode = NORMAL;
ModeConfig config;

void setMode(Mode m) {

    currentMode = m;

    switch(m) {

        case NORMAL:
            config.imuInterval = 20;
            config.ultrasonicInterval = 100;
            break;

        case LOW_POWER:
            config.imuInterval = 100;
            config.ultrasonicInterval = 300;
            break;

        case HIGH_ALERT:
            config.imuInterval = 10;
            config.ultrasonicInterval = 50;
            break;

        case EMERGENCY:
            config.imuInterval = 10;
            config.ultrasonicInterval = 50;
            break;
    }
}
