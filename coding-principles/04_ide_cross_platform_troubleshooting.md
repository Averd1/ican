# 04. IDE and Cross-Platform Troubleshooting Principles

When AI agents develop across embedded C++ (ESP32) and mobile apps (Flutter/Android), the IDE language servers (Clangd, Gradle Daemon) will often throw "false-positive" or environment errors. Use the following principles to diagnose and fix them at the root.

## 1. Clangd Cross-Compilation (Xtensa vs x86)
**The Problem:** The IDE uses an x86 `clangd` language server, but PlatformIO generates compile commands intended for the `xtensa-esp32-elf-g++` cross-compiler. `clangd` will encounter unknown architecture flags (like `-mlongcalls`, `-fstrict-volatile-bitfields`) and crash early, causing cascading `Unknown type` and `file not found` errors.

**The Fix:** 
Always create a `.clangd` file in the project or firmware root to strip cross-compiler flags and tell Clangd the target architecture:
```yaml
CompileFlags:
  Remove:
    - -mlongcalls
    - -fstrict-volatile-bitfields
    - -fno-tree-switch-conversion
  Add:
    - --target=xtensa
    - -DESP32
```
*Note:* `--query-driver` must go in the IDE's VS Code `settings.json` (`clangd.arguments`), **not** in `.clangd`.

## 2. Directory Depth for Shared Headers
**The Problem:** When sharing firmware headers across directories (e.g., `firmware/shared/`), `Unknown type` errors often mean the `#include` path isn't traversing high enough up the directory tree.
**The Fix:** Always verify depth. If a file is in `firmware/ican_cane/lib/haptics/` (3 levels deep), it must use `../../../` to reach `firmware/`. Standardize to absolute paths via PlatformIO `-I` flags where possible to avoid `../../` hell.

## 3. Algorithmic Refuges over Standard Library Battles
**The Problem:** Microcontroller IDE environments frequently struggle to resolve standard C++ headers (`<math.h>`, `std`, `sqrtf`) due to missing sysroot paths in Windows.
**The Fix:** Before spending hours fighting standard library pathing, ask: *Can I solve this with a simpler algorithm?* 
*Example:* Instead of fighting missing `sqrt()` for vector magnitude, compute the **squared magnitude** (`x*x + y*y + z*z`) and compare it to a **squared threshold**. This optimizes embedded performance and sidesteps IDE header limitations entirely.

## 4. Gradle/Kotlin System Java Version Mismatches
**The Problem:** Android build errors like `The supplied phased action failed with an exception. 25.0.1` occur because modern Kotlin compiler plugins aggressively parse the system's `java.version` string. If the developer has a bleeding-edge Java JDK (like Java 25) installed, Gradle crashes.
**The Fix:** Bypass the system JDK by pointing the Gradle daemon to Android Studio's bundled, stable Java version (usually Java 17 or 21). Add this to `android/gradle.properties`:
```properties
org.gradle.java.home=C:/Program Files/Android/Android Studio/jbr
```
*(Use forward slashes for Windows paths in Gradle properties).*
