/*
  Heart Rate (BPM) Measurement — Manual Implementation
  Arduino Nano ESP32 (no PulseSensor Playground library needed)

  Wiring:
    Pulse Sensor S  → A0
    Pulse Sensor +  → 3.3V  (use 3.3V, NOT 5V, on Nano ESP32)
    Pulse Sensor -  → GND
*/

const int PULSE_PIN     = A0;
const int LED_PIN       = LED_BUILTIN;

// --- Tuning parameters ---
const int   SAMPLE_INTERVAL_MS  = 2;     // Sample every 2ms → 500 Hz
const int   HISTORY_SIZE        = 250;   // 500ms of signal history for threshold
const float PEAK_THRESHOLD_FRAC = 0.6;  // Peak must be 60% of the way from min to max
const long  MIN_BEAT_GAP_MS     = 300;  // Ignore beats faster than 200 BPM (300ms gap)
const long  MAX_BEAT_GAP_MS     = 1500; // Ignore gaps longer than 40 BPM (1500ms)
const int   BPM_AVERAGE_COUNT   = 5;    // Average last N inter-beat intervals

// --- State ---
int     signalHistory[HISTORY_SIZE];
int     historyIndex     = 0;
bool    historyFull      = false;

bool    beatInProgress   = false;
long    lastBeatTime     = 0;
long    ibiHistory[BPM_AVERAGE_COUNT];  // Inter-beat interval history (ms)
int     ibiIndex         = 0;
bool    ibiReady         = false;       // True once we have enough IBIs

long    lastSampleTime   = 0;
long    lastPrintTime    = 0;

void setup() {
  Serial.begin(115200);
  delay(1000); // Give serial monitor time to connect
  Serial.println("=== Pulse Sensor Monitor Started ===");
  Serial.println("Place finger firmly on sensor...");

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // Initialize IBI history
  for (int i = 0; i < BPM_AVERAGE_COUNT; i++) ibiHistory[i] = 0;
}

void loop() {
  long now = millis();

  // --- Sample at fixed interval ---
  if (now - lastSampleTime < SAMPLE_INTERVAL_MS) return;
  lastSampleTime = now;

  int raw = analogRead(PULSE_PIN);

  // --- Update rolling signal history ---
  signalHistory[historyIndex] = raw;
  historyIndex = (historyIndex + 1) % HISTORY_SIZE;
  if (historyIndex == 0) historyFull = true;

  // --- Compute dynamic min/max from history ---
  int count = historyFull ? HISTORY_SIZE : historyIndex;
  int sigMin = signalHistory[0], sigMax = signalHistory[0];
  for (int i = 1; i < count; i++) {
    if (signalHistory[i] < sigMin) sigMin = signalHistory[i];
    if (signalHistory[i] > sigMax) sigMax = signalHistory[i];
  }

  // --- Dynamic threshold: 60% between min and max ---
  int amplitude = sigMax - sigMin;
  int threshold = sigMin + (int)(amplitude * PEAK_THRESHOLD_FRAC);

  // --- Beat detection (rising edge crossing threshold) ---
  if (amplitude > 50) { // Ignore flat signal (no finger / bad contact)
    if (!beatInProgress && raw > threshold) {
      // Rising edge — beat start
      beatInProgress = true;
      long gap = now - lastBeatTime;

      if (lastBeatTime > 0 && gap >= MIN_BEAT_GAP_MS && gap <= MAX_BEAT_GAP_MS) {
        // Valid inter-beat interval
        ibiHistory[ibiIndex] = gap;
        ibiIndex = (ibiIndex + 1) % BPM_AVERAGE_COUNT;
        ibiReady = true;

        // Flash LED on beat
        digitalWrite(LED_PIN, HIGH);
      }
      lastBeatTime = now;
    } else if (beatInProgress && raw < threshold) {
      // Falling edge — beat end
      beatInProgress = false;
      digitalWrite(LED_PIN, LOW);
    }
  } else {
    // No finger detected — reset state
    beatInProgress = false;
    digitalWrite(LED_PIN, LOW);
  }

  // --- Print BPM every second ---
  if (now - lastPrintTime >= 1000) {
    lastPrintTime = now;

    if (amplitude <= 50) {
      Serial.println("No finger detected. Place finger firmly on sensor.");
    } else if (!ibiReady) {
      Serial.println("Detecting pulse... keep finger still.");
    } else {
      // Average the IBI history for stable BPM
      long ibiSum = 0;
      int  ibiCount = 0;
      for (int i = 0; i < BPM_AVERAGE_COUNT; i++) {
        if (ibiHistory[i] > 0) {
          ibiSum += ibiHistory[i];
          ibiCount++;
        }
      }
      if (ibiCount > 0) {
        long avgIBI = ibiSum / ibiCount;
        int  bpm    = 60000 / avgIBI;

        Serial.print("BPM: ");
        Serial.print(bpm);
        Serial.print("  |  Signal amplitude: ");
        Serial.print(amplitude);
        Serial.print("  |  Raw: ");
        Serial.println(raw);
      }
    }
  }
}