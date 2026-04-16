import argparse
import json
from pathlib import Path

import pandas as pd


EXPECTED_VERSION = 4


def summarize(csv_path: Path) -> dict:
    df = pd.read_csv(csv_path)
    if df.empty:
        raise RuntimeError("CSV is empty. Cannot analyze BLE data.")

    ts_ok = "ts" in df.columns
    if ts_ok:
        df["ts"] = pd.to_datetime(df["ts"], errors="coerce")
        df = df.dropna(subset=["ts"]).reset_index(drop=True)

    packet_count = len(df)

    if ts_ok and packet_count > 1:
        elapsed_s = (df["ts"].iloc[-1] - df["ts"].iloc[0]).total_seconds()
        dt = df["ts"].diff().dt.total_seconds().dropna()
        packet_rate_hz = packet_count / elapsed_s if elapsed_s > 0 else 0.0
        mean_interval = float(dt.mean()) if not dt.empty else None
        max_interval = float(dt.max()) if not dt.empty else None
        min_interval = float(dt.min()) if not dt.empty else None
    else:
        elapsed_s = None
        packet_rate_hz = None
        mean_interval = None
        max_interval = None
        min_interval = None

    versions = sorted(df["version"].dropna().astype(int).unique().tolist()) if "version" in df.columns else []
    modes = sorted(df["mode"].dropna().astype(int).unique().tolist()) if "mode" in df.columns else []

    summary = {
        "packet_count": packet_count,
        "elapsed_seconds": elapsed_s,
        "packet_rate_hz": packet_rate_hz,
        "packet_interval_mean_s": mean_interval,
        "packet_interval_min_s": min_interval,
        "packet_interval_max_s": max_interval,
        "versions_seen": versions,
        "version_ok": versions == [EXPECTED_VERSION],
        "modes_seen": modes,
        "battery_min": int(df["battery_percent"].min()) if "battery_percent" in df.columns else None,
        "battery_max": int(df["battery_percent"].max()) if "battery_percent" in df.columns else None,
        "heart_min": int(df["heart_bpm"].min()) if "heart_bpm" in df.columns else None,
        "heart_max": int(df["heart_bpm"].max()) if "heart_bpm" in df.columns else None,
        "heart_raw_min": int(df["heart_raw"].min()) if "heart_raw" in df.columns else None,
        "heart_raw_max": int(df["heart_raw"].max()) if "heart_raw" in df.columns else None,
        "fall_count": int(df["fall"].astype(bool).sum()) if "fall" in df.columns else None,
        "high_stress_count": int(df["high_stress"].astype(bool).sum()) if "high_stress" in df.columns else None,
        "obstacle_near_count": int(df["obstacle_near"].astype(bool).sum()) if "obstacle_near" in df.columns else None,
        "obstacle_imminent_count": int(df["obstacle_imminent"].astype(bool).sum()) if "obstacle_imminent" in df.columns else None,
        "imu_ax_min_ms2": float(df["imu_ax_ms2"].min()) if "imu_ax_ms2" in df.columns else None,
        "imu_ax_max_ms2": float(df["imu_ax_ms2"].max()) if "imu_ax_ms2" in df.columns else None,
        "imu_ay_min_ms2": float(df["imu_ay_ms2"].min()) if "imu_ay_ms2" in df.columns else None,
        "imu_ay_max_ms2": float(df["imu_ay_ms2"].max()) if "imu_ay_ms2" in df.columns else None,
        "imu_az_min_ms2": float(df["imu_az_ms2"].min()) if "imu_az_ms2" in df.columns else None,
        "imu_az_max_ms2": float(df["imu_az_ms2"].max()) if "imu_az_ms2" in df.columns else None,
        "ultra_left_min_mm": int(df["ultra_left_mm"].min()) if "ultra_left_mm" in df.columns else None,
        "ultra_left_max_mm": int(df["ultra_left_mm"].max()) if "ultra_left_mm" in df.columns else None,
        "ultra_right_min_mm": int(df["ultra_right_mm"].min()) if "ultra_right_mm" in df.columns else None,
        "ultra_right_max_mm": int(df["ultra_right_mm"].max()) if "ultra_right_mm" in df.columns else None,
        "matrix_head_valid_count": int((df["matrix_head_mm"] != 0xFFFF).sum()) if "matrix_head_mm" in df.columns else None,
        "matrix_waist_valid_count": int((df["matrix_waist_mm"] != 0xFFFF).sum()) if "matrix_waist_mm" in df.columns else None,
        "matrix_head_min_mm": int(df.loc[df["matrix_head_mm"] != 0xFFFF, "matrix_head_mm"].min()) if "matrix_head_mm" in df.columns and (df["matrix_head_mm"] != 0xFFFF).any() else None,
        "matrix_head_max_mm": int(df.loc[df["matrix_head_mm"] != 0xFFFF, "matrix_head_mm"].max()) if "matrix_head_mm" in df.columns and (df["matrix_head_mm"] != 0xFFFF).any() else None,
        "matrix_waist_min_mm": int(df.loc[df["matrix_waist_mm"] != 0xFFFF, "matrix_waist_mm"].min()) if "matrix_waist_mm" in df.columns and (df["matrix_waist_mm"] != 0xFFFF).any() else None,
        "matrix_waist_max_mm": int(df.loc[df["matrix_waist_mm"] != 0xFFFF, "matrix_waist_mm"].max()) if "matrix_waist_mm" in df.columns and (df["matrix_waist_mm"] != 0xFFFF).any() else None,
        "imu_valid_samples": int(df["imu_valid"].astype(bool).sum()) if "imu_valid" in df.columns else None,
        "pulse_valid_samples": int(df["pulse_valid"].astype(bool).sum()) if "pulse_valid" in df.columns else None,
        "battery_valid_samples": int(df["battery_valid"].astype(bool).sum()) if "battery_valid" in df.columns else None,
    }

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyze ProtoSmartCane BLE telemetry CSV")
    parser.add_argument("--file", required=True, help="Path to CSV generated by TestDataRecorder.py")
    parser.add_argument("--save-json", action="store_true", help="Save summary JSON next to CSV")
    args = parser.parse_args()

    csv_path = Path(args.file)
    summary = summarize(csv_path)

    print(json.dumps(summary, indent=2))

    if args.save_json:
        out_path = csv_path.with_suffix(csv_path.suffix + ".summary.json")
        out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"Saved summary: {out_path}")


if __name__ == "__main__":
    main()
