# App Developer Guide - ProtoSmartCane v2.1 Integration

## 📱 What Your App Receives

### BLE Telemetry Packet (5 bytes)

```
Byte 0: Version        = 0x02
Byte 1: Battery %      = 0-100
Byte 2: Current Mode   = 0-4
Byte 3: Heart Rate     = 0-255 BPM
Byte 4: Flags          = Bit flags
```

**Example telemetry:**
- `[0x02, 85, 0, 72, 0x00]` = v2, 85% battery, NORMAL mode, 72 BPM, no alerts

---

## 🔋 Battery Lifetime Calculation

### Power Profile Lookup Table

Store this in your app (these values are fixed in firmware):

```javascript
// JavaScript/React example
const POWER_PROFILES = {
    0: {
        name: "NORMAL",
        powerMA: 85,
        description: "Active continuous navigation"
    },
    1: {
        name: "LOW_POWER",
        powerMA: 50,
        description: "Battery-saving mode (< 20%)"
    },
    2: {
        name: "EMERGENCY",
        powerMA: 250,
        description: "Emergency response (capped 30s)"
    },
    3: {
        name: "CAUTIOUS_SLEEP",
        powerMA: 30,
        description: "Light sleep (5 min inactivity)"
    },
    4: {
        name: "DEEP_SLEEP",
        powerMA: 10.6,
        description: "Deep sleep (20 min inactivity)"
    }
};

const BATTERY_CAPACITY_MAH = 660;
const BATTERY_USABLE = 0.9;  // 90% usable capacity (preserve cell life)
```

### Calculation Function

```javascript
function calculateBatteryLifetime(batteryPercent, modeEnum) {
    // Get power profile for current mode
    const profile = POWER_PROFILES[modeEnum];
    
    if (!profile) {
        console.error(`Unknown mode: ${modeEnum}`);
        return null;
    }
    
    // Calculate usable capacity
    const usableCapacityMAH = BATTERY_CAPACITY_MAH * BATTERY_USABLE;
    
    // Runtime = (Capacity / PowerDraw) × (Battery% / 100)
    const runtimeHours = (usableCapacityMAH / profile.powerMA) * 
                         (batteryPercent / 100);
    
    // Convert to minutes for better display
    const runtimeMinutes = Math.round(runtimeHours * 60);
    
    return {
        hours: runtimeHours.toFixed(1),
        minutes: runtimeMinutes,
        profile: profile.name,
        powerMA: profile.powerMA,
        batteryPercent: batteryPercent
    };
}

// Example usage:
// Battery: 85%, Mode: NORMAL (0)
const estimate = calculateBatteryLifetime(85, 0);
console.log(`Battery: ${estimate.batteryPercent}%, Mode: ${estimate.profile}`);
console.log(`Estimated runtime: ${estimate.hours} hours (${estimate.minutes} minutes)`);
// Output: "Battery: 85%, Mode: NORMAL"
//         "Estimated runtime: 6.8 hours (410 minutes)"
```

### Display Recommendations

```javascript
// React component example
function BatteryStatus({ batteryPercent, mode, heartRate }) {
    const lifetime = calculateBatteryLifetime(batteryPercent, mode);
    
    // Color coding
    let batteryColor = "green";    // > 4 hours
    if (lifetime.runtimeHours < 4) batteryColor = "yellow";   // 1-4 hours
    if (lifetime.runtimeHours < 1) batteryColor = "red";      // < 1 hour
    
    return (
        <div>
            <h3 style={{color: batteryColor}}>
                Battery: {batteryPercent}%
            </h3>
            <p>
                {lifetime.hours} hours remaining 
                ({lifetime.minutes} minutes)
            </p>
            <p>Mode: {lifetime.profile}</p>
            <p>Heart Rate: {heartRate} BPM</p>
            
            {lifetime.runtimeHours < 1 && (
                <div style={{background: "red", color: "white", padding: "10px"}}>
                    ⚠️ Low battery! Charge soon.
                </div>
            )}
            
            {lifetime.runtimeHours < 4 && lifetime.runtimeHours >= 1 && (
                <div style={{background: "yellow", padding: "10px"}}>
                    ⚡ Battery getting low. Plan charging.
                </div>
            )}
        </div>
    );
}
```

---

## 📊 What Changed From v2.0 to v2.1

### BLE Packet Size

**v2.0:** 9 bytes
```cpp
[version][flags][heartBPM][batteryPercent][minDistanceMM (2 bytes)]
[estimatedRuntime][sequenceNumber (2 bytes)]
```

**v2.1:** 5 bytes
```cpp
[version][batteryPercent][currentMode][heartBPM][flags]
```

**Impact:**
- 44% smaller packet = less BLE overhead
- You lose: distance data, sequence number, runtime estimate
- You gain: mode info (for power lookup), cleaner API
- Change required: Implement battery calculation in app

### What You Still Get

✅ Battery percentage (unchanged)  
✅ Heart rate data (unchanged)  
✅ Emergency flags (fall/stress/collision) (unchanged)  
✅ **NEW:** Current mode (for power lookup)

### What You Need to Calculate

❌ Estimated runtime (now app's responsibility)  
❌ Minimum obstacle distance (no longer sent)

**Why?**
- Smaller packets reduce BLE power consumption
- App has plenty of CPU to do the math
- Cane power budget more important than app

---

## 🔄 Update Checklist for Your App

### Step 1: Add Power Profile Data
```javascript
// Add to your constants file
const POWER_PROFILES = { ... };  // See above
```

### Step 2: Implement Calculation Function
```javascript
// Add to your utilities
function calculateBatteryLifetime(batteryPercent, mode) { ... }
```

### Step 3: Update BLE Parser
```javascript
// Old v2.0 parser
const oldPacket = {
    version: data[0],
    flags: data[1],
    heartBPM: data[2],
    batteryPercent: data[3],
    minDistanceMM: (data[4] << 8) | data[5],
    estimatedRuntime: data[6],
    sequenceNumber: (data[7] << 8) | data[8]
};

// New v2.1 parser
const newPacket = {
    version: data[0],
    batteryPercent: data[1],
    currentMode: data[2],
    heartBPM: data[3],
    flags: data[4]
};
```

### Step 4: Update UI Components
```javascript
// Change from displaying cane-calculated runtime to app-calculated
// OLD: Display `packet.estimatedRuntime` minutes directly
// NEW: Calculate using batteryLifetime() function

const lifetime = calculateBatteryLifetime(
    packet.batteryPercent, 
    packet.currentMode
);
console.log(`${lifetime.hours} hours remaining`);
```

### Step 5: Add Alerts & Warnings
```javascript
// When battery < 20% and mode switches to LOW_POWER
if (packet.currentMode === 1 && packet.batteryPercent < 20) {
    showNotification("Low battery mode activated - expect reduced responsiveness");
}

// When battery < 30 minutes remaining
if (calculateBatteryLifetime(batteryPercent, mode).minutes < 30) {
    showWarningBanner("Low battery! Plan to charge soon.");
}

// When emergency detected
if (packet.flags & 0x01) {  // Fall detected
    showAlert("FALL DETECTED - Emergency response active");
}
```

---

## 📈 Example: Full Integration

```javascript
/**
 * ProtoSmartCane v2.1 BLE Integration
 */

class SmartCaneManager {
    constructor() {
        this.POWER_PROFILES = {
            0: { name: "NORMAL", mA: 85 },
            1: { name: "LOW_POWER", mA: 50 },
            2: { name: "EMERGENCY", mA: 250 },
            3: { name: "CAUTIOUS_SLEEP", mA: 30 },
            4: { name: "DEEP_SLEEP", mA: 10.6 }
        };
        
        this.BATTERY_CAPACITY = 660;
        this.BATTERY_USABLE = 0.9;
    }
    
    // Parse incoming BLE packet
    parseTelemetry(data) {
        return {
            version: data[0],
            batteryPercent: data[1],
            currentMode: data[2],
            heartBPM: data[3],
            flags: {
                fallDetected: !!(data[4] & 0x01),
                highStress: !!(data[4] & 0x02),
                obstacleNear: !!(data[4] & 0x04),
                obstacleImminent: !!(data[4] & 0x08)
            }
        };
    }
    
    // Calculate battery lifetime from telemetry
    calculateBatteryLife(telemetry) {
        const profile = this.POWER_PROFILES[telemetry.currentMode];
        const usableCapacity = this.BATTERY_CAPACITY * this.BATTERY_USABLE;
        
        const hours = (usableCapacity / profile.mA) * 
                      (telemetry.batteryPercent / 100);
        
        return {
            hours: parseFloat(hours.toFixed(1)),
            minutes: Math.round(hours * 60),
            mode: profile.name
        };
    }
    
    // Generate user-friendly display
    getStatusDisplay(telemetry) {
        const lifetime = this.calculateBatteryLife(telemetry);
        
        let status = `🔋 ${telemetry.batteryPercent}% - `;
        status += `${lifetime.hours}h remaining (${lifetime.minutes} min)`;
        status += ` [${lifetime.mode}]`;
        
        if (telemetry.flags.fallDetected) {
            status = `🚨 FALL DETECTED - ${status}`;
        } else if (telemetry.flags.highStress) {
            status = `⚠️ HIGH STRESS - ${status}`;
        } else if (telemetry.flags.obstacleImminent) {
            status = `⚡ COLLISION ALERT - ${status}`;
        } else if (telemetry.flags.obstacleNear) {
            status = `🛑 OBSTACLE NEAR - ${status}`;
        }
        
        return status;
    }
}

// Usage
const manager = new SmartCaneManager();

// When BLE packet received
const rawData = [0x02, 85, 0, 72, 0x00];  // Binary data from cane
const telemetry = manager.parseTelemetry(new Uint8Array(rawData));
const lifetime = manager.calculateBatteryLife(telemetry);
const display = manager.getStatusDisplay(telemetry);

console.log(display);
// Output: "🔋 85% - 6.8h remaining (410 min) [NORMAL]"
```

---

## 🎨 UI/UX Recommendations

### Battery Indicator

```
Normal (green): ◆◆◆◆◆ 100% → 8.0h
                ◆◆◆◆◇ 75% → 6.0h
                ◆◆◆◇◇ 50% → 4.0h

Low (yellow):   ◆◆◇◇◇ 25% → 2.0h ⚡

Critical (red): ◆◇◇◇◇ 10% → 0.8h ⚠️
```

### Mode Indicator

```
NORMAL        [◉] Active Navigation     (85 mA)
LOW_POWER     [◐] Battery Saving       (50 mA)
EMERGENCY     [◌] Emergency Response   (250 mA)
SLEEP         [◇] Standby Mode         (10-30 mA)
```

### Alert Messages

```
Priority 1 (RED):
  "🚨 FALL DETECTED!"
  "Battery: X%, Mode: NORMAL, Time: Y hours remaining"

Priority 2 (YELLOW):
  "⚡ Imminent Collision - Haptic + Buzzer Alert"
  "Obstacle <30cm away"

Priority 3 (BLUE):
  "⚠️ Low Battery - Switched to LOW_POWER mode"
  "Runtime reduced to Z hours"

Priority 4 (GREEN):
  "✓ System Normal"
  "Battery X%, Mode: NORMAL, Y hours remaining"
```

---

## 🔧 Troubleshooting

### "Estimated runtime too high"
- Check: Is `BATTERY_CAPACITY_MAH` set to 660?
- Check: Is `BATTERY_USABLE` set to 0.9?
- Check: Did firmware power profile change? (Check config.h)

### "Estimated runtime negative"
- This shouldn't happen. Check for:
  - Mode value out of range (should be 0-4)
  - Battery percent > 100 or < 0
  - Missing power profile entry

### "BLE packet not recognized"
- Verify packet version is 0x02
- Check: First byte = 0x02, not 0x01 (v1 was larger)
- Verify: Packet is exactly 5 bytes

---

## 📞 Quick Reference

| Function | Input | Output | Purpose |
|----------|-------|--------|---------|
| `parseTelemetry(data)` | 5-byte array | telemetry object | Parse BLE packet |
| `calculateBatteryLife(telemetry)` | Telemetry object | {hours, minutes, mode} | Battery lifetime |
| `getStatusDisplay(telemetry)` | Telemetry object | String | User-friendly display |

---

## ✅ Implementation Checklist

- [ ] Add POWER_PROFILES constant to app
- [ ] Implement calculateBatteryLifetime() function
- [ ] Update BLE packet parser for 5-byte format
- [ ] Update UI to display calculated runtime
- [ ] Add low-battery warnings
- [ ] Add emergency alert handling
- [ ] Test with live device
- [ ] Deploy to production

---

**For any questions, refer to:**
- **OPTIMIZATION_GUIDE.md** - Technical background
- **CHANGES_SUMMARY_v2_1.md** - What changed and why
- **config.h** - Firmware constants (power profiles)

**You're ready to integrate! 🎉**
