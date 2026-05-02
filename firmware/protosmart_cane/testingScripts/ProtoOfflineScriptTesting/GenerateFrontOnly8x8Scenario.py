import argparse
import datetime as dt
import json
import math
import random
from pathlib import Path

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots


SENSOR_ERROR_DISTANCE = 65535
NORMAL_MODE = 0
NORMAL_MODE_NAME = "NORMAL"
HIGH_STRESS_MODE = 2
HIGH_STRESS_MODE_NAME = "HIGH_STRESS"
VERSION = 2
SAMPLE_PERIOD_S = 0.2
OBSTACLE_FAR_MM = 1000
OBSTACLE_NEAR_MM = 500
OBSTACLE_IMMINENT_MM = 200
HEART_ABNORMAL_HIGH_BPM = 120
HEART_ABNORMAL_LOW_BPM = 50


def interpolate(start: float, end: float, ratio: float) -> float:
    return start + (end - start) * ratio


def scenario_distance_mm(t_s: float) -> int:
    if t_s < 4.0:
        return SENSOR_ERROR_DISTANCE
    if t_s < 8.0:
        ratio = (t_s - 4.0) / 4.0
        return int(round(interpolate(780.0, 540.0, ratio)))
    if t_s < 11.0:
        ratio = (t_s - 8.0) / 3.0
        return int(round(interpolate(500.0, 260.0, ratio)))
    if t_s < 13.0:
        ratio = (t_s - 11.0) / 2.0
        return int(round(interpolate(210.0, 160.0, ratio)))
    if t_s < 16.0:
        ratio = (t_s - 13.0) / 3.0
        return int(round(interpolate(180.0, 320.0, ratio)))
    if t_s < 20.0:
        ratio = (t_s - 16.0) / 4.0
        return int(round(interpolate(380.0, 760.0, ratio)))
    return SENSOR_ERROR_DISTANCE


def response_band(distance_mm: int) -> int:
    if distance_mm == SENSOR_ERROR_DISTANCE:
        return 0
    if distance_mm <= OBSTACLE_IMMINENT_MM:
        return 3
    if distance_mm <= OBSTACLE_NEAR_MM:
        return 2
    if distance_mm <= OBSTACLE_FAR_MM:
        return 1
    return 0


def packet_flags(distance_mm: int, high_stress: bool) -> int:
    flags = 0
    if distance_mm != SENSOR_ERROR_DISTANCE:
        if distance_mm <= OBSTACLE_IMMINENT_MM:
            flags |= 0x08
        elif distance_mm <= OBSTACLE_NEAR_MM:
            flags |= 0x04
    if high_stress:
        flags |= 0x02
    return flags


def heart_rate_bpm(t_s: float, profile: str, rng: random.Random) -> int:
    if profile == "resting":
        bpm = 72.0 + 2.0 * math.sin(t_s * 0.7) + rng.uniform(-1.0, 1.0)
    elif profile == "post_exercise_recovery":
        # Starts elevated after brief exercise (for example, jumping jacks),
        # then recovers during the obstacle test while remaining below the
        # abnormal-HR threshold so the scenario stays a pure front-obstacle case.
        bpm = 88.0 + 22.0 * math.exp(-t_s / 8.0) + 1.8 * math.sin(t_s * 0.8) + rng.uniform(-1.2, 1.2)
    elif profile == "high_stress_overlap":
        # Exercise-induced elevation intentionally stays above threshold around
        # the imminent-obstacle window to model HIGH_STRESS_EVENT behavior.
        bpm = 104.0 + 20.0 * math.exp(-((t_s - 12.0) ** 2) / 10.0) + 1.5 * math.sin(t_s * 0.9) + rng.uniform(-1.0, 1.0)
    else:
        raise ValueError(f"Unknown heart profile: {profile}")

    bpm = max(45, min(160, int(round(bpm))))
    return bpm


def build_dataframe(duration_s: float, heart_profile: str) -> pd.DataFrame:
    rng = random.Random(441)
    start = dt.datetime(2026, 5, 1, 12, 0, 0)
    rows = []
    sample_count = int(round(duration_s / SAMPLE_PERIOD_S)) + 1

    for index in range(sample_count):
        t_s = index * SAMPLE_PERIOD_S
        timestamp = start + dt.timedelta(seconds=t_s)
        waist_mm = scenario_distance_mm(t_s)
        matrix_detected = waist_mm != SENSOR_ERROR_DISTANCE

        heart_bpm = heart_rate_bpm(t_s, heart_profile, rng)
        battery_percent = 94 if t_s < 18.0 else 93
        high_stress = bool(waist_mm != SENSOR_ERROR_DISTANCE and waist_mm <= OBSTACLE_IMMINENT_MM and heart_bpm > HEART_ABNORMAL_HIGH_BPM)
        flags = packet_flags(waist_mm, high_stress)
        mode = HIGH_STRESS_MODE if high_stress else NORMAL_MODE
        mode_name = HIGH_STRESS_MODE_NAME if high_stress else NORMAL_MODE_NAME

        rows.append(
            {
                "ts": timestamp.isoformat(timespec="milliseconds"),
                "version": VERSION,
                "battery_percent": battery_percent,
            "mode": mode,
            "mode_name": mode_name,
                "heart_bpm": heart_bpm,
                "flags": flags,
                "fall": False,
                "high_stress": high_stress,
                "obstacle_near": bool(flags & 0x04),
                "obstacle_imminent": bool(flags & 0x08),
                "imu_ax_ms2": round(0.20 + rng.uniform(-0.08, 0.08), 2),
                "imu_ay_ms2": round(-6.70 + rng.uniform(-0.18, 0.18), 2),
                "imu_az_ms2": round(7.30 + rng.uniform(-0.18, 0.18), 2),
                "ultra_left_mm": SENSOR_ERROR_DISTANCE,
                "ultra_right_mm": SENSOR_ERROR_DISTANCE,
                "matrix_head_mm": SENSOR_ERROR_DISTANCE,
                "matrix_waist_mm": waist_mm,
                "matrix_head_valid": False,
                "matrix_waist_valid": matrix_detected,
            }
        )

    df = pd.DataFrame(rows)
    df["ts"] = pd.to_datetime(df["ts"])
    df["elapsed_s"] = (df["ts"] - df["ts"].iloc[0]).dt.total_seconds()
    df["heart_abnormal"] = (df["heart_bpm"] > HEART_ABNORMAL_HIGH_BPM) | (df["heart_bpm"] < HEART_ABNORMAL_LOW_BPM)
    return df


def build_summary(df: pd.DataFrame, heart_profile: str) -> dict:
    detected = df[df["matrix_waist_valid"].astype(bool)]
    return {
        "scenario": "front obstacle detected by 8x8 matrix waist zone only",
        "heart_profile": heart_profile,
        "packet_count": int(len(df)),
        "duration_s": float(df["elapsed_s"].iloc[-1]),
        "packet_rate_hz": round(float((len(df) - 1) / max(df["elapsed_s"].iloc[-1], SAMPLE_PERIOD_S)), 3),
        "mode_name": NORMAL_MODE_NAME,
        "heart_bpm_min": int(df["heart_bpm"].min()),
        "heart_bpm_max": int(df["heart_bpm"].max()),
        "heart_abnormal_samples": int(df["heart_abnormal"].astype(bool).sum()),
        "modes_seen": sorted(df["mode_name"].astype(str).unique().tolist()),
        "high_stress_mode_samples": int((df["mode"] == HIGH_STRESS_MODE).sum()),
        "min_matrix_waist_mm": int(detected["matrix_waist_mm"].min()) if not detected.empty else None,
        "max_matrix_waist_mm": int(detected["matrix_waist_mm"].max()) if not detected.empty else None,
        "near_samples": int(df["obstacle_near"].astype(bool).sum()),
        "imminent_samples": int(df["obstacle_imminent"].astype(bool).sum()),
        "high_stress_samples": int(df["high_stress"].astype(bool).sum()),
        "fall_samples": int(df["fall"].astype(bool).sum()),
        "ultrasonic_detection_samples": int(((df["ultra_left_mm"] != SENSOR_ERROR_DISTANCE) | (df["ultra_right_mm"] != SENSOR_ERROR_DISTANCE)).sum()),
        "expected_behavior": {
            "head_haptic": "off throughout",
            "left_haptic": "mirrors right haptic because obstacle is directly ahead",
            "right_haptic": "mirrors left haptic because obstacle is directly ahead",
            "center_disk": "activates only during imminent segment",
            "mode": "stays NORMAL because heart rate stays below abnormal threshold and no fall is present" if heart_profile != "high_stress_overlap" else "would escalate to HIGH_STRESS during the overlap between imminent obstacle and abnormal heart rate",
        },
        "note": "This fixture is enriched for offline analysis. The current firmware BLE packet does not expose obstacle-source bits directly.",
    }


def write_dashboard(df: pd.DataFrame, output_html: Path) -> None:
    x = df["ts"]
    valid_waist = df["matrix_waist_mm"].where(df["matrix_waist_mm"] != SENSOR_ERROR_DISTANCE)
    inferred_response_band = df["matrix_waist_mm"].apply(response_band)
    inferred_left_haptic = inferred_response_band.copy()
    inferred_right_haptic = inferred_response_band.copy()
    inferred_head_haptic = pd.Series([0] * len(df))
    inferred_disk_active = (inferred_response_band == 3).astype(int)

    fig = make_subplots(
        rows=5,
        cols=1,
        shared_xaxes=True,
        vertical_spacing=0.04,
        subplot_titles=(
            "Battery and Heart Rate",
            "Distance Traces",
            "Detection Source Activity",
            "Event Flags and Inferred Response Band",
            "Inferred Actuation From Current Logic",
        ),
        row_heights=[0.18, 0.24, 0.14, 0.18, 0.26],
    )

    fig.add_trace(
        go.Scatter(x=x, y=df["battery_percent"], mode="lines", name="battery_percent", line={"width": 3, "color": "#22c55e"}),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=df["heart_bpm"], mode="lines", name="heart_bpm", line={"width": 3, "color": "#22d3ee"}),
        row=1,
        col=1,
    )
    fig.add_hline(y=HEART_ABNORMAL_HIGH_BPM, line_dash="dash", line_color="#ef4444", row=1, col=1)
    fig.add_hline(y=HEART_ABNORMAL_LOW_BPM, line_dash="dash", line_color="#3b82f6", row=1, col=1)

    fig.add_trace(
        go.Scatter(x=x, y=valid_waist, mode="lines", name="matrix_waist_mm", line={"width": 4, "color": "#22c55e"}),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=[None] * len(df), mode="lines", name="ultra_left_mm (no hit)", line={"dash": "dot", "color": "#64748b"}),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=[None] * len(df), mode="lines", name="ultra_right_mm (no hit)", line={"dash": "dot", "color": "#94a3b8"}),
        row=2,
        col=1,
    )
    fig.add_hline(y=OBSTACLE_NEAR_MM, line_dash="dash", line_color="#f59e0b", row=2, col=1)
    fig.add_hline(y=OBSTACLE_IMMINENT_MM, line_dash="dash", line_color="#ef4444", row=2, col=1)

    fig.add_trace(
        go.Scatter(x=x, y=df["matrix_waist_valid"].astype(int), mode="lines", name="matrix_detected", line={"shape": "hv", "width": 3, "color": "#22c55e"}),
        row=3,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=[0] * len(df), mode="lines", name="ultra_left_detected", line={"shape": "hv", "dash": "dot", "color": "#64748b"}),
        row=3,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=[0] * len(df), mode="lines", name="ultra_right_detected", line={"shape": "hv", "dash": "dot", "color": "#94a3b8"}),
        row=3,
        col=1,
    )

    fig.add_trace(
        go.Scatter(x=x, y=df["obstacle_near"].astype(int), mode="lines", name="obstacle_near", line={"shape": "hv", "width": 3, "color": "#f59e0b"}),
        row=4,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=df["obstacle_imminent"].astype(int), mode="lines", name="obstacle_imminent", line={"shape": "hv", "width": 3, "color": "#ef4444"}),
        row=4,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=df["high_stress"].astype(int), mode="lines", name="high_stress", line={"shape": "hv", "width": 3, "color": "#a855f7"}),
        row=4,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=inferred_response_band, mode="lines", name="response_band", line={"shape": "hv", "width": 3, "color": "#38bdf8"}),
        row=4,
        col=1,
    )

    fig.add_trace(
        go.Scatter(x=x, y=inferred_left_haptic, mode="lines", name="left_haptic", line={"shape": "hv", "width": 3, "color": "#a855f7"}),
        row=5,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=inferred_right_haptic, mode="lines", name="right_haptic", line={"shape": "hv", "width": 3, "dash": "dot", "color": "#ec4899"}),
        row=5,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=inferred_head_haptic, mode="lines", name="head_haptic", line={"shape": "hv", "width": 3, "color": "#64748b"}),
        row=5,
        col=1,
    )
    fig.add_trace(
        go.Scatter(x=x, y=inferred_disk_active, mode="lines", name="disk_active", line={"shape": "hv", "width": 3, "color": "#f97316"}),
        row=5,
        col=1,
    )

    fig.update_layout(
        title="Synthetic Offline Test Fixture: Front Obstacle Detected by 8x8 Waist Zone Only",
        template="plotly_dark",
        height=1500,
        legend={"orientation": "h", "yanchor": "bottom", "y": 1.02, "xanchor": "right", "x": 1},
    )
    fig.update_xaxes(title_text="Timestamp", row=5, col=1)
    fig.update_yaxes(title_text="Battery / BPM", row=1, col=1)
    fig.update_yaxes(title_text="Distance (mm)", row=2, col=1)
    fig.update_yaxes(title_text="Detected", row=3, col=1, tickmode="array", tickvals=[0, 1], ticktext=["No", "Yes"])
    fig.update_yaxes(title_text="State", row=4, col=1, tickmode="array", tickvals=[0, 1, 2, 3], ticktext=["Clear", "Far", "Near", "Imminent"])
    fig.update_yaxes(title_text="Actuation", row=5, col=1, tickmode="array", tickvals=[0, 1, 2, 3], ticktext=["Off", "Far", "Near", "Imminent"])

    fig.write_html(output_html)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate synthetic front-only 8x8 obstacle telemetry for offline BLE plots")
    parser.add_argument("--duration", type=float, default=24.0, help="Scenario duration in seconds")
    parser.add_argument(
        "--heart-profile",
        choices=["resting", "post_exercise_recovery", "high_stress_overlap"],
        default="post_exercise_recovery",
        help="Heart-rate profile to synthesize for the scenario",
    )
    parser.add_argument(
        "--output-base",
        default=str(Path(__file__).resolve().parent / "synthetic_front_8x8_only"),
        help="Base path for generated CSV/HTML/JSON outputs",
    )
    args = parser.parse_args()

    output_base = Path(args.output_base)
    output_base.parent.mkdir(parents=True, exist_ok=True)

    df = build_dataframe(args.duration, args.heart_profile)
    csv_path = output_base.with_suffix(".csv")
    html_path = output_base.with_suffix(".focused_dashboard.html")
    summary_path = output_base.with_suffix(".summary.json")

    df.to_csv(csv_path, index=False)
    write_dashboard(df, html_path)
    summary_path.write_text(json.dumps(build_summary(df, args.heart_profile), indent=2), encoding="utf-8")

    print(f"Saved CSV: {csv_path}")
    print(f"Saved focused dashboard: {html_path}")
    print(f"Saved summary: {summary_path}")


if __name__ == "__main__":
    main()