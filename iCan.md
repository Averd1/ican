# iCan Device

The iCan is a modified walking cane for the visually impaired.

For better organization, the total project is broken down into two independent modules:

1) The iCan Cane
2) The iCan Eye

## Components

### iCan Cane
- Arduino Nano ESP32
- 1 TF Luna - LiDAR sensor
- 2 Ultrasonic Distance Sensors
- DRV2605L Haptic Driver
- 3 Vibration Motors
- 4400mAh Li-Po Battery
- 5626 STEMMA QT 8‑CHAN I2C MUX PCA954, is an I²C multiplexer (allows for multiple I2C devices to be connected to the same I2C bus)
- Adafruit Mini GPS
- Pulse Sensor
- Folding Graphite Cane (https://www.amazon.com/Ambutech-4-Sec-Folding-Graphite-Cane-Marsh-50-in/dp/B01M18KWDQ)
- LSM6DSOX (IMU)

### iCan Eye
- XIAO ESP32-S3 Sense
- 1200mAh Li-Po Battery
- Mini Oval Speaker

# iCan Cane Product Description
The iCan Cane uses a lidar sensor to detect obstacles at head height of the user attached to the top of the cane after the placement of the handle. The two ultrasonic sensors are placed together lower on the cane, but not the bottom tip of the cane. The two ultrasonic sensors are in a cornered attached together.

The iCan Cane's handle will have three haptic motors embedded in the handle. The motors will shape a triangle on the handle, a vibration motor is placed on the left side of the handle, a vibration motor is placed on the right side of the handle, and a vibration motor is placed on the top of the handle. Their respective purpose is to alert the user of obstacles. Object detection on the left side of the cane will trigger the left haptic motor, object detection on the right side of the cane will trigger the right haptic motor, and object detection at the head level of the user will trigger the top haptic motor.

## The Free Nav
The Free Nav part of the Smart Cane represents the haptic and object detection via the 3 sensors attached. This subsystem is done on the microcontroller in terms of running the logic described above. There is another subsystem in the cane that is to leverage GPS and the haptic motors to guide the user to a specific destination that is inputted via their iCan App.

## The Guided Nav
The Guided Nav part of the iCan Cane that represents a separate feature of using walking GPS (using a SDK like mapbox) and the haptic motor subsystem of the cane to guide the user to a specific destination.

## Design Challenge #1
How will the logic of the haptic motors be created given the two features of GPS (Guided Nav) and Free Nav (Object Detection)? As the device ideally should be able to detect objects to help the user to avoid them and to also (when Guided Nav is enabled) guide the user to a specific destination.

### Sensor Integration
To help with the logic for integrating inputs from the LiDAR and ultrasonic sensors, consider the following approach:
- The LiDAR sensor detects obstacles at head height.
- The ultrasonic sensors detect obstacles at lower levels.
- The IMU can provide orientation data to understand the cane's position.

For coding languages, C++ is commonly used with Arduino, and libraries like the Arduino IDE can be leveraged for sensor integration.

## Design Challenge #2
Given the three inputs, 2 ultrasonic sensors and 1 lidar sensor. What is the optimal implementation logic on triggering the haptic motors? Considering the left-right sweeping motion of the cane when naturally used. Also considering the IMU to leverage knowledge of the direction and movement of the cane.

## Design Challenge #3
It is a serious consideration to just use the ESP32 to take the picture and send it to the phone and have the phone do the object detection and audio output. As there are libraries that can be installed in the phone (via the iCan app read more in ./README.md)
that can provide faster and run a more accurate model.

### Image Processing
Offloading the image processing to the user's smartphone is a reasonable approach given the computational power of modern smartphones. This will also allow for more complex models to be run without worrying about the limitations of the microcontroller. However, consider the latency and power consumption implications.

# iCan Eye Product Description
The iCan Eye is a device that is worn as a necklace for the user. The purpose of this product is to provide an additional layer of awareness by leveraging object detection models and an audio output that describes the environment around the user. The iCan Eye is a microcontroller with a camera where the user can press a button and the device will take a picture of what is in front of the user.
