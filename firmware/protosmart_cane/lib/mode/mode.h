/*
 * Power Mode Management Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"

void setMode(SystemMode newMode);
int getBatteryLevel();