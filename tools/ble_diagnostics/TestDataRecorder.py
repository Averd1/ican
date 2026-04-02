import asyncio
from bleak import BleakClient
import pandas as pd
import datetime

ADDRESS = "PUT_YOUR_SMARTCANE_ADDRESS_HERE"
CHAR_UUID = "abcd1234-ab12-cd34-ef56-1234567890ab"

data = []

def handle_notification(sender, data_bytes):
    line = data_bytes.decode().strip()
    values = line.split(",")

    # EXPECT 8 VALUES FOR: ax, ay, az, dist_left, dist_right, lux, heart, mode 
    if len(values) == 8:
        data.append(values)
        print(values)

async def main():
    async with BleakClient(ADDRESS) as client:
        print("Connected")

        await client.start_notify(CHAR_UUID, handle_notification)

        input("Press ENTER to stop recording")

        await client.stop_notify(CHAR_UUID)

    df = pd.DataFrame(data, columns=[
        "ax","ay","az",
        "dist_left","dist_right",
        "lux",
        "heart",
        "mode"
    ])

    filename = "smartcane_ble_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + ".csv"

    df.to_csv(filename, index=False)

    print("Saved:", filename)

asyncio.run(main())