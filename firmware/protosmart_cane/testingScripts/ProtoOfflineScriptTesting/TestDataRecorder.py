import argparse
import asyncio
import datetime
import struct
import time

import pandas as pd
from bleak import BleakClient, BleakScanner


DEVICE_NAME = "ProtoSmartCane"
CHAR_UUID = "abcd1234-5678-5678-5678-abcd12345678"

MODE_MAP = {
    0: "NORMAL",
    1: "LOW_POWER",
    2: "HIGH_STRESS",
    3: "EMERGENCY",
}

data = []


def decode_flags(flags: int) -> dict:
    return {
        "fall": bool(flags & 0x01),
        "high_stress": bool(flags & 0x02),
        "obstacle_near": bool(flags & 0x04),
        "obstacle_imminent": bool(flags & 0x08),
    }


def handle_notification(_sender, data_bytes: bytearray) -> None:
    # TelemetryPacket v2 (packed, 5 bytes): version, battery%, mode, heart, flags
    if len(data_bytes) < 5:
        return

    version, battery_percent, mode, heart_bpm, flags = struct.unpack("<BBBBB", data_bytes[:5])
    flag_bits = decode_flags(flags)
    mode_name = MODE_MAP.get(mode, f"UNKNOWN_{mode}")

    row = {
        "ts": datetime.datetime.now().isoformat(timespec="milliseconds"),
        "version": version,
        "battery_percent": battery_percent,
        "mode": mode,
        "mode_name": mode_name,
        "heart_bpm": heart_bpm,
        "flags": flags,
        "fall": flag_bits["fall"],
        "high_stress": flag_bits["high_stress"],
        "obstacle_near": flag_bits["obstacle_near"],
        "obstacle_imminent": flag_bits["obstacle_imminent"],
    }
    data.append(row)

    print(
        f"{row['ts']} | v{version} | batt={battery_percent}% | "
        f"mode={mode_name}({mode}) | hr={heart_bpm} | flags=0x{flags:02X}"
    )


async def resolve_address(explicit_address: str | None) -> str:
    if explicit_address:
        return explicit_address

    print(f"No address provided, scanning for {DEVICE_NAME}...")
    devices = await BleakScanner.discover(timeout=8.0)
    for dev in devices:
        if dev.name == DEVICE_NAME:
            print(f"Found {DEVICE_NAME} at {dev.address}")
            return dev.address

    raise RuntimeError(
        f"Could not find {DEVICE_NAME}. Ensure BLE is enabled, advertising, and nearby."
    )


async def main() -> None:
    parser = argparse.ArgumentParser(description="Record ProtoSmartCane BLE telemetry (v2)")
    parser.add_argument("--address", help="BLE MAC address (optional; auto-discovers by name if omitted)")
    parser.add_argument("--char", default=CHAR_UUID, help="Characteristic UUID to subscribe")
    parser.add_argument("--duration", type=float, default=20.0, help="Capture duration in seconds for non-interactive mode")
    parser.add_argument("--min-packets", type=int, default=1, help="Fail if fewer packets are captured")
    parser.add_argument("--interactive", action="store_true", help="Use ENTER key to stop instead of fixed duration")
    parser.add_argument("--wait-start-key", action="store_true", help="Wait for ENTER before starting BLE capture")
    args = parser.parse_args()

    address = await resolve_address(args.address)

    async with BleakClient(address) as client:
        if not client.is_connected:
            raise RuntimeError("Failed to connect to BLE device")

        print(f"Connected to {address}")

        if args.wait_start_key:
            input("Press ENTER to begin capture...\n")

        start = time.monotonic()
        await client.start_notify(args.char, handle_notification)

        if args.interactive:
            input("Press ENTER to stop recording...\n")
        else:
            print(f"Recording for {args.duration:.1f}s...")
            await asyncio.sleep(args.duration)

        await client.stop_notify(args.char)
        elapsed = time.monotonic() - start
        print(f"Capture complete: {len(data)} packets in {elapsed:.2f}s")

    if len(data) < args.min_packets:
        raise RuntimeError(
            f"Insufficient BLE packets captured ({len(data)} < {args.min_packets})."
        )

    df = pd.DataFrame(data)
    filename = "smartcane_ble_v2_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + ".csv"
    df.to_csv(filename, index=False)
    print("Saved:", filename)


if __name__ == "__main__":
    asyncio.run(main())