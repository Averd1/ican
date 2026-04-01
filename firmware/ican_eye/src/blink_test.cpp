#include <Arduino.h>

void setup() {
  // Built-in LED on Seeed XIAO ESP32S3 is pin 21 (active low)
  pinMode(21, OUTPUT);
  Serial.begin(115200);
}

void loop() {
  digitalWrite(21, LOW); // Turn ON LED
  Serial.println("LED ON - I am alive!");
  delay(1000);
  
  digitalWrite(21, HIGH); // Turn OFF LED
  Serial.println("LED OFF");
  delay(1000);
}
