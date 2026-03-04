# Coding Principle: C/C++ Include Ordering (Arduino/ESP32)

## Rule
**Always include core framework headers before third-party or local headers.**

## Standard Order (top to bottom)
1. `<Arduino.h>`, `<Wire.h>`, `<SPI.h>` — Core framework
2. `<Adafruit_LSM6DSOX.h>`, `<NimBLEDevice.h>` — Third-party libraries
3. `"sensors.h"`, `"ble_comm.h"` — Local project headers

## Why
`Arduino.h` defines types (`uint8_t`), macros (`HIGH`, `LOW`, `OUTPUT`), and functions (`delay()`, `pulseIn()`, `Serial`). If a third-party library is included first, the compiler can't resolve these symbols yet.

## Correct
```cpp
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include "sensors.h"
```

## Incorrect
```cpp
#include "sensors.h"           // may reference uint8_t
#include <Adafruit_LSM6DSOX.h> // needs Arduino types
#include <Arduino.h>           // too late
```
