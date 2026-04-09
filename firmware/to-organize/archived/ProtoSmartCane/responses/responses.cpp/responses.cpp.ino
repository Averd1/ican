#include "responses.h"
// Situation enum defined in fusion module
enum Situation { NONE, OBJECT_FAR, OBJECT_NEAR, OBJECT_IMMINENT, FALL_DETECTED, LOW_LIGHT, HIGH_STRESS };
extern Situation currentSituation;
#include <Arduino.h>

// Hardware pin definitions for actuators
#define BUZZER_PIN 9
#define LED_PIN 6

// Buzzer control variables
unsigned long lastBuzz = 0;
bool buzzerState = false;

// Emergency response state
static bool emergencyActive = false;
static unsigned long emergencyStartTime = 0;
static const unsigned long EMERGENCY_DURATION = 30000; // 30 seconds of emergency alerts

void initActuators() {
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(LED_PIN, OUTPUT);

    // Ensure actuators start in off state
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(LED_PIN, LOW);
}

void setLED(int brightness) {
    // Set LED brightness (0-255) using PWM
    analogWrite(LED_PIN, brightness);
}

void buzzerPulse(int intervalMs) {
    // Pulse buzzer at specified interval for different alert patterns
    if (millis() - lastBuzz > intervalMs) {
        buzzerState = !buzzerState;
        digitalWrite(BUZZER_PIN, buzzerState);
        lastBuzz = millis();
    }
}

void buzzerOff() {
    digitalWrite(BUZZER_PIN, LOW);
    buzzerState = false;
}

void handleResponse() {
    // Main response handler - maps situations to appropriate user feedback
    // Priority-based response system for different detected situations

    switch(currentSituation) {
        case OBJECT_FAR:
            // Gentle alert for distant obstacles
            buzzerPulse(300);  // Slow pulse
            setLED(100);       // Dim LED
            emergencyActive = false;
            break;

        case OBJECT_NEAR:
            // Moderate alert for closer obstacles
            buzzerPulse(150);  // Medium pulse
            setLED(180);       // Medium brightness
            emergencyActive = false;
            break;

        case OBJECT_IMMINENT:
            // Urgent alert for very close obstacles
            buzzerPulse(50);   // Fast pulse
            setLED(255);       // Full brightness
            emergencyActive = false;
            break;

        case FALL_DETECTED:
            // EMERGENCY: Fall detected - highest priority alert
            handleFallResponse();
            emergencyActive = true;
            emergencyStartTime = millis();
            break;

        case HIGH_STRESS:
            // Emergency: High stress condition (close obstacle + abnormal heart rate)
            buzzerPulse(25);   // Very fast pulse
            setLED(255);       // Full brightness
            emergencyActive = true;
            emergencyStartTime = millis();
            break;

        case LOW_LIGHT:
            // Visual alert only for low light conditions
            buzzerOff();
            setLED(255);
            emergencyActive = false;
            break;

        default:
            // No situation detected - turn off all alerts
            buzzerOff();
            setLED(0);
            emergencyActive = false;
            break;
    }

    // Emergency timeout - prevent indefinite emergency alerts
    if (emergencyActive && (millis() - emergencyStartTime > EMERGENCY_DURATION)) {
        emergencyActive = false;
        buzzerOff();
        setLED(100);  // Keep LED dim to indicate system is still active
    }
}

void handleFallResponse() {
    // Specialized fall response - maximum alert intensity
    Serial.println(" !!! FALL DETECTED - EMERGENCY RESPONSE ACTIVE !!!");

    // Continuous buzzer and full LED brightness
    digitalWrite(BUZZER_PIN, HIGH);
    setLED(255);
}
