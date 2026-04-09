/*
 * Response System Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"
#include "led_driver.h"
#include "haptic_driver.h"

void responsesInit();
void setLED(int brightness);
void buzzerPulse(unsigned long intervalMs);
void buzzerOff();
void handleResponses();
void handleFallResponse();