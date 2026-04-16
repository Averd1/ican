import argparse
import asyncio
import datetime
import struct
import time

import pandas as pd
from bleak import BleakClient, BleakScanner


DEVICE_NAME = "ProtoSmartCane"
CHAR_UUID = "abcd1234-5678-5678-5678-abcd12345678"
V2_PACKET_LEN = 5
V3_PACKET_LEN = 19
V4_PACKET_LEN = 22

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
    if len(data_bytes) < V2_PACKET_LEN:
        return

    version, battery_percent, mode, heart_bpm, flags = struct.unpack("<BBBBB", data_bytes[:V2_PACKET_LEN])
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

    if version >= 4 and len(data_bytes) >= V4_PACKET_LEN:
        (
            sensor_status,
            imu_ax_cms2,
            imu_ay_cms2,
            imu_az_cms2,
            ultra_left_mm,
            ultra_right_mm,
            matrix_head_mm,
            matrix_waist_mm,
            heart_raw,
        ) = struct.unpack("<BhhhHHHHH", data_bytes[V2_PACKET_LEN:V4_PACKET_LEN])

        row["sensor_status"] = int(sensor_status)
        row["imu_valid"] = bool(sensor_status & 0x01)
        row["ultra_left_valid"] = bool(sensor_status & 0x02)
        row["ultra_right_valid"] = bool(sensor_status & 0x04)
        row["matrix_head_valid"] = bool(sensor_status & 0x08)
        row["matrix_waist_valid"] = bool(sensor_status & 0x10)
        row["pulse_valid"] = bool(sensor_status & 0x20)
        row["battery_valid"] = bool(sensor_status & 0x40)

        row["imu_ax_ms2"] = None if imu_ax_cms2 == -32768 else float(imu_ax_cms2) / 100.0
        row["imu_ay_ms2"] = None if imu_ay_cms2 == -32768 else float(imu_ay_cms2) / 100.0
        row["imu_az_ms2"] = None if imu_az_cms2 == -32768 else float(imu_az_cms2) / 100.0
        row["ultra_left_mm"] = int(ultra_left_mm)
        row["ultra_right_mm"] = int(ultra_right_mm)
        row["matrix_head_mm"] = int(matrix_head_mm)
        row["matrix_waist_mm"] = int(matrix_waist_mm)
        row["heart_raw"] = int(heart_raw)
    elif version >= 3 and len(data_bytes) >= V3_PACKET_LEN:
        (
            imu_ax_cms2,
            imu_ay_cms2,
            imu_az_cms2,
            ultra_left_mm,
            ultra_right_mm,
            matrix_head_mm,
            matrix_waist_mm,
        ) = struct.unpack("<hhhHHHH", data_bytes[V2_PACKET_LEN:V3_PACKET_LEN])

        row["imu_ax_ms2"] = float(imu_ax_cms2) / 100.0
        row["imu_ay_ms2"] = float(imu_ay_cms2) / 100.0
        row["imu_az_ms2"] = float(imu_az_cms2) / 100.0
        row["ultra_left_mm"] = int(ultra_left_mm)
        row["ultra_right_mm"] = int(ultra_right_mm)
        row["matrix_head_mm"] = int(matrix_head_mm)
        row["matrix_waist_mm"] = int(matrix_waist_mm)
        row["matrix_head_valid"] = int(matrix_head_mm) != 0xFFFF
        row["matrix_waist_valid"] = int(matrix_waist_mm) != 0xFFFF

    data.append(row)

    line = (
        f"{row['ts']} | v{version} | batt={battery_percent}% | "
        f"mode={mode_name}({mode}) | hr={heart_bpm} | flags=0x{flags:02X}"
    )
    if version >= 3 and "ultra_left_mm" in row:
        line += (
            f" | ultra(L/R)={row['ultra_left_mm']}/{row['ultra_right_mm']} mm"
            f" | 8x8(H/W)={row['matrix_head_mm']}/{row['matrix_waist_mm']} mm"
        )
    if version >= 4 and "heart_raw" in row:
        line += f" | pulseRaw={row['heart_raw']}"
    if version >= 3 and row.get("imu_ax_ms2") is not None:
        line += f" | imu(ax,ay,az)={row['imu_ax_ms2']:.2f},{row['imu_ay_ms2']:.2f},{row['imu_az_ms2']:.2f}"
    print(line)


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
    parser.add_argument("--connect-timeout", type=float, default=20.0, help="BLE connect timeout in seconds")
    parser.add_argument("--connect-retries", type=int, default=3, help="Number of BLE connect attempts before failing")
    parser.add_argument("--retry-delay", type=float, default=2.0, help="Seconds to wait between retries")
    args = parser.parse_args()

    base_address = await resolve_address(args.address)

    for attempt in range(1, args.connect_retries + 1):
        try:
            # BLE private/random addresses can rotate; refresh address per retry when auto-discovering.
            address = base_address if args.address else await resolve_address(None)
            print(f"Connecting to {address} (attempt {attempt}/{args.connect_retries})...")
            async with BleakClient(
                address,
                timeout=args.connect_timeout,
                winrt={"use_cached_services": False},
            ) as client:
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
                break
        except Exception as exc:
            if attempt == args.connect_retries:
                raise RuntimeError(
                    f"BLE connection failed after {args.connect_retries} attempts: {exc}"
                ) from exc
            print(f"Connect attempt failed: {type(exc).__name__}: {exc}. Retrying in {args.retry_delay:.1f}s...")
            await asyncio.sleep(args.retry_delay)

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