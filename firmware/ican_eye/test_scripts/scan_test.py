import asyncio
from bleak import BleakScanner

async def main():
    print("Scanning for 5 seconds...")
    devices = await BleakScanner.discover(timeout=5.0)
    for d in devices:
        if d.name:
            print(f"Name: {d.name}, Address: {d.address}")

if __name__ == "__main__":
    asyncio.run(main())
