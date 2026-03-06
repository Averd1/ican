// iCan Cane - Prototype 1: Dual Ultrasonic Sensors with LED Feedback
// Hardware: ESP32-WROOM-32, 2x HC-SR04 Ultrasonic Sensors, 2x LEDs

// ---------------------------------------------------------
// Pin Definitions (Change these based on your actual wiring)
// ---------------------------------------------------------

// Left Sensor Pins
const int TRIG_PIN_L = 5;
const int ECHO_PIN_L = 18;
// Left LED Pin (Haptic Motor Representation)
const int LED_PIN_L = 22;

// Right Sensor Pins
const int TRIG_PIN_R = 19;
const int ECHO_PIN_R = 21;
// Right LED Pin (Haptic Motor Representation)
const int LED_PIN_R = 23;

// ---------------------------------------------------------
// Configuration Parameters
// ---------------------------------------------------------

// Active distance range in cm (Tweak for the cane's desired sensitivity)
const int MIN_DISTANCE = 5;   // Closer than 5cm = fastest vibration
const int MAX_DISTANCE = 200; // Further than 2m (200cm) = no vibration

// Blink intervals in milliseconds (mapping distance to speed)
const int MIN_BLINK_INTERVAL = 50; // Fastest blink interval (50ms on, 50ms off)
const int MAX_BLINK_INTERVAL =
    800; // Slowest blink interval (800ms on, 800ms off)

// ---------------------------------------------------------
// State Variables for Non-blocking Blinking
// ---------------------------------------------------------

unsigned long previousMillisL = 0;
bool ledStateL = false;

unsigned long previousMillisR = 0;
bool ledStateR = false;

void setup() {
  Serial.begin(115200); // ESP32 prefers 115200 baud rate in the serial monitor

  // Configure Pins
  pinMode(TRIG_PIN_L, OUTPUT);
  pinMode(ECHO_PIN_L, INPUT);
  pinMode(LED_PIN_L, OUTPUT);

  pinMode(TRIG_PIN_R, OUTPUT);
  pinMode(ECHO_PIN_R, INPUT);
  pinMode(LED_PIN_R, OUTPUT);

  // Initialize LEDs to OFF
  digitalWrite(LED_PIN_L, LOW);
  digitalWrite(LED_PIN_R, LOW);

  Serial.println("iCan Prototype 1: Dual Ultrasonic Sensor test starting...");
}

void loop() {
  // 1. Read distances sequentially to prevent acoustic crosstalk
  float distanceL_cm = readDistance(TRIG_PIN_L, ECHO_PIN_L);
  float distanceR_cm = readDistance(TRIG_PIN_R, ECHO_PIN_R);

  // 2. Print distances for debugging via Serial Monitor
  Serial.print("Left: ");
  Serial.print(distanceL_cm);
  Serial.print(" cm | Right: ");
  Serial.print(distanceR_cm);
  Serial.println(" cm");

  // 3. Update LED blink speeds based on distance
  updateFeedbackDevice(distanceL_cm, LED_PIN_L, previousMillisL, ledStateL);
  updateFeedbackDevice(distanceR_cm, LED_PIN_R, previousMillisR, ledStateR);

  // 4. Small delay to stabilize loop and allow echo signals to dissipate
  delay(50);
}

// Function to read ultrasonic distance securely
float readDistance(int trigPin, int echoPin) {
  // Ensure the trigger pin is low before sending a pulse
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);

  // Send a 10 microsecond pulse to trigger the sensor
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);

  // Read the echo pin.
  // 25000 microsecond timeout (~400cm travel time) prevents loop from freezing!
  long duration = pulseIn(echoPin, HIGH, 25000);

  if (duration == 0) {
    return MAX_DISTANCE + 1; // Out of range or no reading detected
  }

  // Calculate distance in cm (Speed of sound is approx. 0.0343 cm/us)
  float distance = (duration / 2.0) * 0.0343;
  return distance;
}

// Function to calculate blink interval and update LED state without blocking
// code
void updateFeedbackDevice(float distance, int pin, unsigned long &prevMillis,
                          bool &ledState) {
  if (distance > MAX_DISTANCE) {
    // Out of range: Turn off LED immediately
    digitalWrite(pin, LOW);
    ledState = false;
    return;
  }

  // Constrain distance within our configured bounds
  float constrainedDist = constrain(distance, MIN_DISTANCE, MAX_DISTANCE);

  // Map the distance to a blink interval.
  // Closer distance matches with a smaller interval (faster
  // blinking/vibrating).
  unsigned long interval = map(constrainedDist, MIN_DISTANCE, MAX_DISTANCE,
                               MIN_BLINK_INTERVAL, MAX_BLINK_INTERVAL);

  // Using millis() for non-blocking toggling
  unsigned long currentMillis = millis();
  if (currentMillis - prevMillis >= interval) {
    prevMillis = currentMillis; // save the last time we blinked the LED
    ledState = !ledState;       // Flip state
    digitalWrite(pin, ledState ? HIGH : LOW);
  }
}