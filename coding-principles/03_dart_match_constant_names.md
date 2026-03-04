# Coding Principle: Always Verify Dart Constant Names Against Source Definitions

## Rule
When referencing constants from a protocol/shared file (e.g., `ble_protocol.dart`), always verify the exact field name. Do not assume or invent names.

## Why
Using a non-existent getter (e.g., `BleServices.icanCaneUuid` when the actual name is `BleServices.caneServiceUuid`) causes a compile error that is easy to miss in a large diff. The protocol file is the single source of truth.

## Checklist
1. Open the protocol file (`lib/protocol/ble_protocol.dart`).
2. Copy the exact constant name.
3. Paste it into your service/consumer code.

## Correct
```dart
// ble_protocol.dart defines: static const String caneServiceUuid = '...';
Guid(BleServices.caneServiceUuid)
```

## Incorrect
```dart
// Invented name — does not exist
Guid(BleServices.icanCaneUuid)
```
