// Pin Definitions
const int TRIG_R = D3;
const int ECHO_R = D2;
const int TRIG_L = D6;
const int ECHO_L = D5;
const int LED_R = D4;
const int LED_L = D7;

// LED blink config
const int DIST_MAX = 200;
const int DIST_MIN = 20;
const int BLINK_SLOW = 800;
const int BLINK_FAST = 80;

// LED state
bool ledLState = false;
bool ledRState = false;
bool activateL = false;
bool activateR = false;
unsigned long lastBlinkTime = 0;
int blinkInterval = BLINK_SLOW;

// Sensor read timing
unsigned long lastSensorRead = 0;
const int SENSOR_INTERVAL = 300;

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

  pinMode(TRIG_L, OUTPUT);
  pinMode(TRIG_R, OUTPUT);
  pinMode(ECHO_L, INPUT);
  pinMode(ECHO_R, INPUT);

  pinMode(LED_L, OUTPUT);
  pinMode(LED_R, OUTPUT);

  digitalWrite(TRIG_L, HIGH);
  digitalWrite(TRIG_R, HIGH);

  digitalWrite(LED_L, LOW);
  digitalWrite(LED_R, LOW);

  delay(1000);
  Serial.println("--- DEBUG START ---");
}

int getBlinkInterval(int dist) {
  if (dist <= 0 || dist >= DIST_MAX) return -1;
  if (dist <= DIST_MIN) return BLINK_FAST;
  return map(dist, DIST_MIN, DIST_MAX, BLINK_FAST, BLINK_SLOW);
}

void loop() {
  unsigned long now = millis();

  // --- Sensor reads ---
  if (now - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = now;

    long distL = readDistanceCm(TRIG_L, ECHO_L);
    delay(30); // avoid crosstalk
    long distR = readDistanceCm(TRIG_R, ECHO_R);

    Serial.print("L: "); Serial.print(distL);
    Serial.print("cm | R: "); Serial.print(distR); Serial.println("cm");

    // --- Direction logic ---
    activateL = false;
    activateR = false;

    if (distL > 0 && distL < 150 && distR > 0 && distR < 150) {
      if (abs(distL - distR) < 15) {
        Serial.println(">> FRONT");
        activateL = true;
        activateR = true;
      } else if (distL < distR) {
        Serial.println(">> LEFT");
        activateL = true;
      } else {
        Serial.println(">> RIGHT");
        activateR = true;
      }
    } else if (distL > 0 && distL < 150) {
      Serial.println(">> LEFT ONLY");
      activateL = true;
    } else if (distR > 0 && distR < 150) {
      Serial.println(">> RIGHT ONLY");
      activateR = true;
    }

    // --- Determine blink speed ---
    int closestDist = -1;

    if (activateL && activateR) {
      closestDist = min(distL, distR);
    } else if (activateL) {
      closestDist = distL;
    } else if (activateR) {
      closestDist = distR;
    }

    if (closestDist > 0) {
      int interval = getBlinkInterval(closestDist);
      if (interval > 0) {
        blinkInterval = interval;
      } else {
        activateL = false;
        activateR = false;
      }
    }
  }

  // --- Blink logic ---
  if (!activateL && !activateR) {
    digitalWrite(LED_L, LOW);
    digitalWrite(LED_R, LOW);
    ledLState = false;
    ledRState = false;
  } else {
    if (now - lastBlinkTime >= (unsigned long)blinkInterval) {
      lastBlinkTime = now;

      // LEFT LED (independent toggle)
      if (activateL) {
        ledLState = !ledLState;
        digitalWrite(LED_L, ledLState ? HIGH : LOW);
      } else {
        digitalWrite(LED_L, LOW);
        ledLState = false;
      }

      // RIGHT LED (independent toggle)
      if (activateR) {
        ledRState = !ledRState;
        digitalWrite(LED_R, ledRState ? HIGH : LOW);
      } else {
        digitalWrite(LED_R, LOW);
        ledRState = false;
      }
    }
  }

  // No delay → keeps timing accurate
}