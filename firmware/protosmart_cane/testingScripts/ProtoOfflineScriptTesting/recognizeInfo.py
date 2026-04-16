import asyncio
from bleak import BleakScanner


TARGET_NAME = "ProtoSmartCane"


async def scan() -> None:
    devices = await BleakScanner.discover(timeout=8.0)
    print("Discovered BLE devices:")
    for d in devices:
        name = d.name or "<no-name>"
        marker = " <= target" if name == TARGET_NAME else ""
        print(f"{d.address} : {name}{marker}")


if __name__ == "__main__":
    asyncio.run(scan())