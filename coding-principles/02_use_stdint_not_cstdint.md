# Coding Principle: Use `<stdint.h>` instead of `<cstdint>` in Headers

## Rule
In `.h` header files for Arduino/ESP32 firmware, use `#include <stdint.h>` instead of `#include <cstdint>`.

## Why
`<cstdint>` is a C++ standard library header. The IDE's clangd analyzer often cannot locate it because it doesn't have the ESP32 C++ toolchain in its search path. `<stdint.h>` is the C equivalent that provides the same types (`uint8_t`, `int16_t`, etc.) and is universally resolvable by both the PlatformIO compiler and the IDE's language server.

## Correct
```cpp
#include <stdint.h>   // works everywhere
```

## Incorrect
```cpp
#include <cstdint>    // IDE clangd can't find this for ESP32
```
