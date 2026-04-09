#pragma once

// Response system for haptic/audio feedback based on detected situations
// Provides user alerts through buzzer and LED for different cane states

void initActuators();
void setLED(int val);
void buzzerPulse(int speed);
void buzzerOff();
void handleResponse();
void handleFallResponse();
