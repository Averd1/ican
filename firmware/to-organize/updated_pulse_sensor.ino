#include <PulseSensorPlayground.h>

const int PulseWire = A0;
const int LED = LED_BUILTIN;

int Threshold = 2000;   // LOWER this for ESP32

PulseSensorPlayground pulseSensor;

void setup() {
  Serial.begin(115200);
  delay(1000);

  pulseSensor.analogInput(PulseWire);
  pulseSensor.blinkOnPulse(LED);
  pulseSensor.setThreshold(Threshold);

  if (pulseSensor.begin()) {
    Serial.println("PulseSensor ready!");
  }
}

void loop() {

  // Let the library read the signal
  int signal = pulseSensor.getLatestSample();

  //Serial.print("Signal: ");
  //Serial.print(signal);

  if (pulseSensor.sawStartOfBeat()) {
    int myBPM = pulseSensor.getBeatsPerMinute();

    Serial.print("   ♥ Beat detected! BPM: ");
    Serial.println(myBPM);
  }

  Serial.println();

  delay(50);
}