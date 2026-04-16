/*
 * BLE Communication Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"

void bleInit();
void updateBLETelemetry();
void blePoll();