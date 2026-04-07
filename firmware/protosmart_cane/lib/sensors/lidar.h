/*
 * LiDAR Sensor Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"
#include "../mux/mux.h"

void lidarInit();
void lidarUpdate();
uint16_t readLidarDistance();