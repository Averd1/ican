#include <Wire.h>
#include "DFRobot_matrixLidarDistanceSensor.h"

// ───── ToF SETUP ─────
TwoWire I2C_2 = TwoWire(1);
DFRobot_matrixLidarDistanceSensor tof(0x33, &I2C_2);

#define SDA_2 D6
#define SCL_2 D7

#define DIST_THRESHOLD 1500
#define MIN_DIST ((uint16_t)400)

uint16_t buf[64];

// ───── ULTRASONIC ─────
#define TRIG_R D3
#define ECHO_R D2
#define TRIG_L D5
#define ECHO_L D4

// ───── LEDs ─────
#define LED_TOP   D9
#define LED_RIGHT D10
#define LED_LEFT  D11

// ───── TIMERS ─────
unsigned long headTimer = 0;
unsigned long waistTimer = 0;

bool headState = false;
bool waistState = false;

// ───── FUNCTION ─────
long readDistanceCm(int trigPin, int echoPin) {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(5);
  digitalWrite(trigPin, HIGH);
  long duration = pulseIn(echoPin, LOW, 50000);

  if (duration == 0 || duration >= 50000) return -1;
  return duration / 50;
}

void setup() {
  Serial.begin(115200);

  // LEDs
  pinMode(LED_TOP, OUTPUT);
  pinMode(LED_LEFT, OUTPUT);
  pinMode(LED_RIGHT, OUTPUT);

  // Ultrasonic
  pinMode(TRIG_L, OUTPUT);
  pinMode(TRIG_R, OUTPUT);
  pinMode(ECHO_L, INPUT);
  pinMode(ECHO_R, INPUT);

  digitalWrite(TRIG_L, HIGH);
  digitalWrite(TRIG_R, HIGH);

  // ✅ FIXED I2C INIT (THIS WAS THE ISSUE)
  I2C_2.begin(SDA_2, SCL_2);
  delay(2000);

  while (tof.begin() != 0) {
    Serial.println("ToF begin error");
    delay(1000);
  }

  while (tof.getAllDataConfig(eMatrix_8X8) != 0) {
    Serial.println("ToF init error");
    delay(1000);
  }

  Serial.println("System Ready");
}

void loop() {

  // ───── TOF READ ─────
  tof.getAllData(buf);

  bool headDetected = false;
  bool waistFrontDetected = false;

  uint16_t closestHead = 9999;
  uint16_t closestWaist = 9999;

  for (int i = 0; i < 64; i++) {
    uint16_t d = buf[i];
    if (d == 0 || d > DIST_THRESHOLD) continue;

    int row = i / 8;
    int col = i % 8;

    // Head detection
    if (row < 4) {
      headDetected = true;
      if (d < closestHead) closestHead = d;
    }

    // Waist front detection
    if (row >= 4 && col >= 1 && col <= 6) {
      waistFrontDetected = true;
      if (d < closestWaist) closestWaist = d;
    }
  }

  // ───── ULTRASONIC READ ─────
  long distL = readDistanceCm(TRIG_L, ECHO_L);
  delay(20);
  long distR = readDistanceCm(TRIG_R, ECHO_R);

  bool leftDetected  = (distL > 0 && distL < 150);
  bool rightDetected = (distR > 0 && distR < 150);

  // Convert to mm for comparison
  uint16_t left_mm  = leftDetected  ? (uint16_t)(distL * 10) : 9999;
  uint16_t right_mm = rightDetected ? (uint16_t)(distR * 10) : 9999;
  uint16_t front_mm = waistFrontDetected ? closestWaist : 9999;

  // ───── FIND CLOSEST OBSTACLE ─────
  uint16_t closest = min(front_mm, min(left_mm, right_mm));

  // ───── BLINK SPEED BASED ON DISTANCE ─────
  int interval = 500;
  if (closest < 9999) {
    uint16_t d = max(closest, MIN_DIST);
    interval = map(d, MIN_DIST, DIST_THRESHOLD, 50, 500);
  }

  unsigned long now = millis();

  // ───── HEAD LED (independent) ─────
  if (headDetected) {
    if (now - headTimer >= interval) {
      headTimer = now;
      headState = !headState;
      digitalWrite(LED_TOP, headState);
    }
  } else {
    digitalWrite(LED_TOP, LOW);
  }

  // ───── WAIST PRIORITY SYSTEM ─────
  if (closest < 9999) {

    if (now - waistTimer >= interval) {
      waistTimer = now;
      waistState = !waistState;

      // Reset LEDs
      digitalWrite(LED_LEFT, LOW);
      digitalWrite(LED_RIGHT, LOW);

      if (closest == front_mm) {
        // Front → both LEDs
        digitalWrite(LED_LEFT, waistState);
        digitalWrite(LED_RIGHT, waistState);
      }
      else if (closest == left_mm) {
        // Left only
        digitalWrite(LED_LEFT, waistState);
      }
      else if (closest == right_mm) {
        // Right only
        digitalWrite(LED_RIGHT, waistState);
      }
    }
  } else {
    // No obstacle
    digitalWrite(LED_LEFT, LOW);
    digitalWrite(LED_RIGHT, LOW);
  }

  delay(20);
}