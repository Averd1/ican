/*
 * Response System Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"
#include "haptic_driver.h"

void responsesInit();
void vibrationDiskPulse(unsigned long intervalMs);
void vibrationDiskOff();
void handleResponses();
void handleFallResponse();