import argparse
import asyncio
import datetime
import json
import pathlib
import struct
import time

import pandas as pd
from bleak import BleakClient, BleakScanner


DEVICE_NAME = "ProtoSmartCane"
CHAR_UUID = "abcd1234-5678-5678-5678-abcd12345678"
EXPECTED_VERSION = 3
V2_PACKET_LEN = 5
V3_PACKET_LEN = 19

MODE_MAP = {
    0: "NORMAL",
    1: "LOW_POWER",
    2: "HIGH_STRESS",
    3: "EMERGENCY",
}


def decode_flags(flags: int) -> dict:
    return {
        "fall": bool(flags & 0x01),
        "high_stress": bool(flags & 0x02),
        "obstacle_near": bool(flags & 0x04),
        "obstacle_imminent": bool(flags & 0x08),
    }


async def resolve_address(explicit_address: str | None, scan_timeout: float) -> str:
    if explicit_address:
        return explicit_address

    print(f"Scanning for {DEVICE_NAME} for {scan_timeout:.1f}s...")
    devices = await BleakScanner.discover(timeout=scan_timeout)
    for dev in devices:
        if dev.name == DEVICE_NAME:
            print(f"Found {DEVICE_NAME} at {dev.address}")
            return dev.address

    raise RuntimeError(f"Could not find {DEVICE_NAME}. Check BLE advertising and distance.")


async def capture_packets(address: str, char_uuid: str, duration_s: float) -> list[dict]:
    rows: list[dict] = []

    def on_notify(_sender, data_bytes: bytearray) -> None:
        if len(data_bytes) < V2_PACKET_LEN:
            return
        version, battery_percent, mode, heart_bpm, flags = struct.unpack("<BBBBB", data_bytes[:V2_PACKET_LEN])
        decoded_flags = decode_flags(flags)
        row = {
            "ts": datetime.datetime.now().isoformat(timespec="milliseconds"),
            "version": int(version),
            "battery_percent": int(battery_percent),
            "mode": int(mode),
            "mode_name": MODE_MAP.get(int(mode), f"UNKNOWN_{int(mode)}"),
            "heart_bpm": int(heart_bpm),
            "flags": int(flags),
            "fall": decoded_flags["fall"],
            "high_stress": decoded_flags["high_stress"],
            "obstacle_near": decoded_flags["obstacle_near"],
            "obstacle_imminent": decoded_flags["obstacle_imminent"],
        }
        if version >= 3 and len(data_bytes) >= V3_PACKET_LEN:
            imu_ax_cms2, imu_ay_cms2, imu_az_cms2, ultra_left_mm, ultra_right_mm, matrix_head_mm, matrix_waist_mm = struct.unpack(
                "<hhhHHHH", data_bytes[V2_PACKET_LEN:V3_PACKET_LEN]
            )
            row["imu_ax_ms2"] = float(imu_ax_cms2) / 100.0
            row["imu_ay_ms2"] = float(imu_ay_cms2) / 100.0
            row["imu_az_ms2"] = float(imu_az_cms2) / 100.0
            row["ultra_left_mm"] = int(ultra_left_mm)
            row["ultra_right_mm"] = int(ultra_right_mm)
            row["matrix_head_mm"] = int(matrix_head_mm)
            row["matrix_waist_mm"] = int(matrix_waist_mm)
            row["matrix_head_valid"] = int(matrix_head_mm) != 0xFFFF
            row["matrix_waist_valid"] = int(matrix_waist_mm) != 0xFFFF
        rows.append(row)

    async with BleakClient(address) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")

        print(f"Connected to {address}")
        await client.start_notify(char_uuid, on_notify)

        start = time.monotonic()
        await asyncio.sleep(duration_s)
        elapsed = time.monotonic() - start

        await client.stop_notify(char_uuid)

    print(f"Captured {len(rows)} packet(s) in {elapsed:.2f}s")
    return rows


def build_summary(rows: list[dict], duration_s: float, min_packets: int) -> dict:
    packet_count = len(rows)
    packet_rate_hz = packet_count / duration_s if duration_s > 0 else 0.0

    versions = sorted({int(r["version"]) for r in rows}) if rows else []
    modes_seen = sorted({int(r["mode"]) for r in rows}) if rows else []

    summary = {
        "pass": packet_count >= min_packets,
        "expected_version": EXPECTED_VERSION,
        "packet_count": packet_count,
        "min_packets_required": min_packets,
        "capture_duration_s": duration_s,
        "packet_rate_hz": round(packet_rate_hz, 3),
        "versions_seen": versions,
        "version_ok": versions == [EXPECTED_VERSION] if versions else False,
        "modes_seen": modes_seen,
        "mode_names_seen": [MODE_MAP.get(m, f"UNKNOWN_{m}") for m in modes_seen],
        "battery_min": min((int(r["battery_percent"]) for r in rows), default=None),
        "battery_max": max((int(r["battery_percent"]) for r in rows), default=None),
        "heart_min": min((int(r["heart_bpm"]) for r in rows), default=None),
        "heart_max": max((int(r["heart_bpm"]) for r in rows), default=None),
        "any_fall_flag": any(bool(r["fall"]) for r in rows),
        "any_high_stress_flag": any(bool(r["high_stress"]) for r in rows),
        "any_obstacle_near_flag": any(bool(r["obstacle_near"]) for r in rows),
        "any_obstacle_imminent_flag": any(bool(r["obstacle_imminent"]) for r in rows),
        "ultra_left_min_mm": min((int(r["ultra_left_mm"]) for r in rows if "ultra_left_mm" in r), default=None),
        "ultra_left_max_mm": max((int(r["ultra_left_mm"]) for r in rows if "ultra_left_mm" in r), default=None),
        "ultra_right_min_mm": min((int(r["ultra_right_mm"]) for r in rows if "ultra_right_mm" in r), default=None),
        "ultra_right_max_mm": max((int(r["ultra_right_mm"]) for r in rows if "ultra_right_mm" in r), default=None),
        "matrix_head_min_mm": min((int(r["matrix_head_mm"]) for r in rows if "matrix_head_mm" in r and int(r["matrix_head_mm"]) != 0xFFFF), default=None),
        "matrix_head_max_mm": max((int(r["matrix_head_mm"]) for r in rows if "matrix_head_mm" in r and int(r["matrix_head_mm"]) != 0xFFFF), default=None),
        "matrix_waist_min_mm": min((int(r["matrix_waist_mm"]) for r in rows if "matrix_waist_mm" in r and int(r["matrix_waist_mm"]) != 0xFFFF), default=None),
        "matrix_waist_max_mm": max((int(r["matrix_waist_mm"]) for r in rows if "matrix_waist_mm" in r and int(r["matrix_waist_mm"]) != 0xFFFF), default=None),
    }

    return summary


async def main() -> None:
    parser = argparse.ArgumentParser(description="ProtoSmartCane BLE automated capture pipeline")
    parser.add_argument("--address", help="BLE MAC address (optional)")
    parser.add_argument("--scan-timeout", type=float, default=8.0, help="Scan timeout in seconds")
    parser.add_argument("--char", default=CHAR_UUID, help="Characteristic UUID")
    parser.add_argument("--duration", type=float, default=20.0, help="Capture duration in seconds")
    parser.add_argument("--min-packets", type=int, default=10, help="Minimum packets required for pass")
    parser.add_argument("--out-dir", default=".", help="Output directory for CSV and JSON summary")
    args = parser.parse_args()

    address = await resolve_address(args.address, args.scan_timeout)
    rows = await capture_packets(address, args.char, args.duration)

    summary = build_summary(rows, args.duration, args.min_packets)

    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = out_dir / f"smartcane_ble_pipeline_{stamp}.csv"
    json_path = out_dir / f"smartcane_ble_pipeline_{stamp}.summary.json"

    pd.DataFrame(rows).to_csv(csv_path, index=False)
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"CSV: {csv_path}")
    print(f"Summary: {json_path}")
    print(json.dumps(summary, indent=2))

    if not summary["pass"]:
        raise RuntimeError("BLE pipeline failed minimum packet requirement")


if __name__ == "__main__":
    asyncio.run(main())
