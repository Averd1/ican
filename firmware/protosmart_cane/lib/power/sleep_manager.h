/*
 * Sleep Manager - Inactivity Detection and Sleep Mode Transitions
 * Monitors user activity and transitions to low-power sleep modes
 */

#pragma once

#include "../include/state.h"
#include "../include/power_profile.h"

enum SleepMode {
    SLEEP_NONE,
    SLEEP_CAUTIOUS,   // Light sleep, still responsive to obstacles
    SLEEP_DEEP        // Deep sleep, wake-on-move only
};

struct SleepState {
    SleepMode currentSleepMode;
    unsigned long lastMotionTime;
    unsigned long lastTouchTime;
    bool canEnterSleep;
    StateHistory history[STATE_HISTORY_SIZE];
    uint8_t historyIndex;
};

extern SleepState sleepState;

void sleepManagerInit();
void updateSleepManager();
void recordStateHistory();
bool isSafeToSleep();
void enterCautiousSleep();
void enterDeepSleep();
void wakeFromSleep();