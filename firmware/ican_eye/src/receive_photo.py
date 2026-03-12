"""
receive_photo.py — iCan Eye BLE Photo Receiver

Connects to the XIAO ESP32-S3 'XIAO_Camera' BLE device, sends a CAPTURE
command, and receives a JPEG image using the reliable chunked protocol
(sequence-numbered chunks + CRC32 verification).

Requirements:
    pip install bleak

Usage:
    python receive_photo.py
"""

import asyncio
import struct
import zlib
import os
from datetime import datetime
from bleak import BleakClient, BleakScanner

# Must match the UUIDs in ble_camera.ino
SERVICE_UUID  = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
DATA_CHAR     = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
CONTROL_CHAR  = "beb5483f-36e1-4688-b7f5-ea07361b26a8"

SEQ_HEADER_SIZE = 2
MAX_RETRIES = 2

# ---------- Transfer state ----------
class TransferState:
    def __init__(self):
        self.reset()

    def reset(self):
        self.expected_size = 0
        self.expected_crc = None
        self.expected_chunks = 0
        self.chunks = {}          # seq_num -> bytes
        self.receiving = False
        self.transfer_done = False
        self.error = None


state = TransferState()


def handle_control_notification(sender, data: bytearray):
    """Handle SIZE, CRC, and END messages from the control characteristic."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        print(f"  [WARN] Non-text control message: {data.hex()}")
        return

    if text.startswith("SIZE:"):
        state.reset()
        state.expected_size = int(text.split(":")[1])
        state.receiving = True
        print(f"\n  Incoming image: {state.expected_size:,} bytes")

    elif text.startswith("CRC:"):
        state.expected_crc = text.split(":")[1].strip().upper()
        print(f"  Expected CRC32: {state.expected_crc}")

    elif text.startswith("END"):
        # END:<total_chunk_count>
        parts = text.split(":")
        if len(parts) > 1:
            state.expected_chunks = int(parts[1])
        state.receiving = False
        state.transfer_done = True
        print(f"\n  Transfer complete signal received ({state.expected_chunks} chunks expected)")

    else:
        print(f"  [CTRL] {text}")


def handle_data_notification(sender, data: bytearray):
    """Handle image data chunks (2-byte seq header + payload)."""
    if not state.receiving:
        return

    if len(data) < SEQ_HEADER_SIZE:
        print(f"  [WARN] Runt packet: {len(data)} bytes")
        return

    # Unpack little-endian uint16 sequence number
    seq_num = struct.unpack("<H", data[:SEQ_HEADER_SIZE])[0]
    payload = data[SEQ_HEADER_SIZE:]

    state.chunks[seq_num] = bytes(payload)

    # Progress display
    received_bytes = sum(len(v) for v in state.chunks.values())
    if state.expected_size > 0:
        pct = min(100, received_bytes * 100 // state.expected_size)
        bar_len = 30
        filled = pct * bar_len // 100
        bar = "█" * filled + "░" * (bar_len - filled)
        print(f"  [{bar}] {pct:3d}%  {received_bytes:,}/{state.expected_size:,} bytes  (chunk #{seq_num})", end="\r")


def assemble_image() -> tuple[bytearray | None, list[int]]:
    """Assemble chunks in order. Returns (image_data, missing_seq_list)."""
    if not state.chunks:
        return None, []

    max_seq = max(state.chunks.keys())
    total_expected = state.expected_chunks if state.expected_chunks > 0 else (max_seq + 1)

    missing = [i for i in range(total_expected) if i not in state.chunks]

    # Assemble in order
    image_data = bytearray()
    for i in range(max_seq + 1):
        if i in state.chunks:
            image_data.extend(state.chunks[i])

    return image_data, missing


def validate_image(image_data: bytearray) -> tuple[bool, str]:
    """Validate JPEG header/footer and CRC32. Returns (ok, message)."""
    errors = []

    # Check size
    if state.expected_size > 0 and len(image_data) != state.expected_size:
        errors.append(f"Size mismatch: got {len(image_data):,}, expected {state.expected_size:,}")

    # JPEG markers
    if len(image_data) >= 2:
        if image_data[0] != 0xFF or image_data[1] != 0xD8:
            errors.append(f"Bad JPEG header: {image_data[:2].hex()} (expected FFD8)")
    if len(image_data) >= 2:
        if image_data[-2] != 0xFF or image_data[-1] != 0xD9:
            errors.append(f"Bad JPEG footer: {image_data[-2:].hex()} (expected FFD9)")

    # CRC32
    if state.expected_crc:
        actual_crc = format(zlib.crc32(image_data) & 0xFFFFFFFF, "08X")
        if actual_crc != state.expected_crc:
            errors.append(f"CRC mismatch: got {actual_crc}, expected {state.expected_crc}")
        else:
            print(f"  CRC32 OK: {actual_crc}")

    if errors:
        return False, "; ".join(errors)
    return True, "Image validated successfully"


def save_image(image_data: bytearray) -> str:
    """Save image with timestamped filename. Returns the filename."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"photo_{timestamp}.jpg"
    with open(filename, "wb") as f:
        f.write(image_data)
    return filename


async def capture_one(client: BleakClient) -> bool:
    """Send CAPTURE and wait for the transfer. Returns True if image is valid."""
    state.reset()

    print("\nSending CAPTURE command...")
    await client.write_gatt_char(CONTROL_CHAR, b"CAPTURE")

    # Wait for transfer to complete (up to 120 seconds)
    for _ in range(240):
        await asyncio.sleep(0.5)
        if state.transfer_done:
            break

    if not state.transfer_done:
        print("\n  [ERROR] Transfer timed out")
        return False

    print()  # newline after progress bar

    # Assemble and validate
    image_data, missing = assemble_image()

    if missing:
        print(f"  [WARN] Missing {len(missing)} chunk(s): {missing[:20]}{'...' if len(missing) > 20 else ''}")

    if image_data is None or len(image_data) == 0:
        print("  [ERROR] No image data received")
        return False

    ok, msg = validate_image(image_data)
    if ok:
        filename = save_image(image_data)
        abs_path = os.path.abspath(filename)
        print(f"  ✓ Saved: {abs_path} ({len(image_data):,} bytes)")
        return True
    else:
        print(f"  ✗ Validation failed: {msg}")
        # Save anyway with a _bad suffix so user can inspect
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        bad_file = f"photo_{timestamp}_BAD.jpg"
        with open(bad_file, "wb") as f:
            f.write(image_data)
        print(f"  (Saved corrupt image as {bad_file} for inspection)")
        return False


async def main():
    print("=" * 50)
    print("  iCan Eye — BLE Photo Receiver")
    print("=" * 50)
    print("\nScanning for XIAO_Camera...")

    device = await BleakScanner.find_device_by_name("XIAO_Camera", timeout=15)

    if not device:
        print("[ERROR] Device not found.")
        print("  • Is the ESP32 powered on?")
        print("  • Is it advertising (check Serial Monitor)?")
        print("  • Is Bluetooth enabled on this computer?")
        return

    print(f"Found: {device.name} ({device.address})")

    async with BleakClient(device) as client:
        print(f"Connected! (MTU: {client.mtu_size})")

        # Subscribe to notifications on BOTH characteristics
        await client.start_notify(DATA_CHAR, handle_data_notification)
        await client.start_notify(CONTROL_CHAR, handle_control_notification)

        # Attempt capture with retries
        for attempt in range(1, MAX_RETRIES + 2):  # +2 because range is exclusive
            if attempt > 1:
                print(f"\n--- Retry {attempt - 1}/{MAX_RETRIES} ---")

            success = await capture_one(client)
            if success:
                break
            elif attempt <= MAX_RETRIES:
                print("  Retrying in 2 seconds...")
                await asyncio.sleep(2)
            else:
                print(f"\n  [ERROR] All {MAX_RETRIES + 1} attempts failed.")

        await client.stop_notify(DATA_CHAR)
        await client.stop_notify(CONTROL_CHAR)

    print("\nDone.")


if __name__ == "__main__":
    asyncio.run(main())