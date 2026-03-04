# iCan Project: Technical Review & Development Timeline

## 1. Technical Review & Unclear Details
As a technical reviewer, I have reviewed `iCan.md` and `README.md`. It is a well-thought-out project with great potential, but as expected with continuous integration, some architectural details need to be explicitly defined before development begins to avoid blockers:

1. **iCan Eye Wireless Protocol & Scene Description Architecture:**

   **Consideration: Dual-Pipeline Approach.** A single button press on the iCan Eye triggers two parallel pipelines:
   - **Pipeline 1 — "Instant Safety" (Edge AI on XIAO, <1 second):** The XIAO ESP32-S3 runs a local TFLite Micro model (via [SenseCraft AI](https://sensecraft.seeed.cc/ai/model)) to detect basic objects ("person", "car", "stairs"). It sends only the result text over BLE to the phone for immediate TTS output.
   - **Pipeline 2 — "Rich Scene Description" (BLE Image Transfer → Phone-Local VLM, 3-5 seconds):** Simultaneously, the XIAO downscales the captured image to 640x480 JPEG (~30-50 KB) and streams it over **BLE 5.0** (using 2M PHY + Data Length Extension for ~400-700 kbps throughput) to the phone in ~1 second. The phone then runs a **local on-device Vision Language Model** to generate a full scene description (e.g., *"You are on a sidewalk. To your right is a fire hydrant. Two people are walking towards you. There is a crosswalk ahead with the sign reading WALK."*). The phone reads this aloud via TTS.
   - **Cloud Vision API (Fallback Only):** If the local phone model's output quality is insufficient after experimentation, the app falls back to sending the image to a cloud Vision API (Google Gemini Vision or OpenAI GPT-4V). This is the backup plan, not the primary approach.

   **BLE Image Transfer Implementation Notes:**
   - Use **L2CAP Connection-Oriented Channels (CoC)** for streaming (better throughput than GATT characteristics).
   - Negotiate **2M PHY and DLE** at BLE connection time (supported by ESP32-S3, Android 8+, iOS 11+).
   - Chunk the JPEG into ~240-byte packets with sequence headers and a simple checksum.

   **On-Device Phone Vision Models to Research:**
   The primary goal is to find a model that runs locally on modern smartphones and produces rich, natural-language scene descriptions. Models to evaluate:
   - **Apple Vision Framework + VisionKit** (iOS only) — Apple's built-in on-device image analysis, text recognition (Live Text), and scene classification. Free, no API calls, highly optimized for iPhone.
   - **Google ML Kit Image Labeling + Text Recognition** (Android & iOS) — Google's on-device ML suite. Runs locally, labels objects and reads text. Free.
   - **MLC LLM (Machine Learning Compilation)** — Framework for running full LLMs/VLMs on phones. Supports models like LLaVA, Phi-3-Vision, and MiniCPM-V on-device with GPU acceleration.
   - **LLaVA (Large Language and Vision Assistant)** — Open-source VLM. Quantized versions (4-bit) can run on modern phones via MLC LLM. Produces natural scene descriptions.
   - **Microsoft Phi-3-Vision** — Small but powerful multimodal model. Designed for edge deployment. 4-bit quantized versions fit on phones with 6GB+ RAM.
   - **MiniCPM-V** — Lightweight open-source VLM specifically designed for mobile deployment. Strong scene description capabilities at small model sizes (~2-3GB).
   - **moondream2** — Ultra-lightweight VLM (~1.8B params). Can describe scenes and answer questions about images. Small enough to run on most modern phones.
   - **Florence-2 (Microsoft)** — Compact vision foundation model with captioning, OCR, and object detection in a single model. Good candidate for quantized on-device deployment.
   - **Google MediaPipe + Gemini Nano** (Android only) — Google's on-device AI via the AICore system service on Pixel and Samsung devices. Supports multimodal input.
   - **ONNX Runtime Mobile** — Framework for running ONNX models on phones. Can be used to deploy any of the above models that export to ONNX format.

   > **Research Task:** Experiment with the above models on a test phone. Capture sample images of sidewalks, crosswalks, storefronts, and indoor spaces. Run each model and compare the richness and accuracy of the scene description output. Document which model best balances quality, speed, and phone compatibility.

2. **Audio Output Location:** the `iCan.md` mentions a "Mini Oval Speaker" on the iCan Eye, but the App is designed to read aloud and recognize voice commands. Does the audio description play through the phone speaker, wireless earbuds, or the iCan Eye's mini speaker? 

1) the option is up to the user to either do wireless earbuds or the iCan Eye's mini speaker

3. **Conflict Resolution (Haptic Logic):** If the Mapbox GPS tells the user to turn left (triggering the left motor), but the left ultrasonic sensor detects an obstacle, how do they differentiate? *Recommendation:* Use distinct haptic vibration patterns via the DRV2605L (e.g., pulsing for navigation, solid/intense vibration for obstacles) and prioritize obstacle avoidance over navigation.
4. **IMU Cane Sweep Logic:** When a user naturally sweeps the cane left and right, the left sensor might temporarily point forward. The IMU logic needs to calculate the absolute orientation of the cane to accurately map sensor data to real-world left/right/forward obstacles.

---

## 2. Recommended Workflow & Process
The best approach for this embedded + mobile project is **Bottom-Up for Hardware** and **Core-to-Edge for the App**, followed by strict integration phases.
- **Phase 1:** Validate individual hardware components (Sensors & Motors).
- **Phase 2:** Establish baseline communications (BLE/Wi-Fi).
- **Phase 3:** Develop standalone App modules (Voice, GPS, ML).
- **Phase 4:** Integration and Complex Logic (The "Design Challenges").

---

## 3. Development Timeline & Task List
These tasks are detailed enough to be delegated to separate AI agents, embedded engineers, or app developers.

### Phase 1: Hardware Validation & Drivers (Week 1)
**Goal:** Ensure all microcontrollers can read from sensors and write to actuators without overlapping errors.
- [ ] **Task 1.1: Cane I2C Setup.** Connect the TCA9548A (or PCA9546) I2C Multiplexer to the Arduino Nano ESP32. Write a script to scan all I2C channels and verify the DRV2605L, TF Luna LiDAR, and IMU (LSM6DSOX) are detected.
- [ ] **Task 1.2: Cane Haptic Feedback.** Initialize the DRV2605L. Create wrapper functions to trigger distinct haptic waveforms (e.g., `playObstacleLeft()`, `playNavRight()`, `playHeadWarning()`).
- [ ] **Task 1.3: Cane Sensor Polling.** Write a FreeRTOS task or non-blocking timer logic to poll the 2 Ultrasonic sensors (using GPIO interrupts or `pulseIn` non-blocking) and the TF Luna LiDAR via serial or I2C.
- [ ] **Task 1.4: iCan Eye Camera Test.** Set up the XIAO ESP32-S3. Write a script to initialize the camera, take a picture when the button is pressed, and save it to PSRAM.

### Phase 2: Communications & Middleware (Week 2)
**Goal:** Establish the bridge between the microcontrollers and the App.
- [ ] **Task 2.1: Cane BLE Peripheral Setup.** On the Arduino Nano ESP32, set up a BLE Server using the `NimBLE` or standard `BLE` library. Create specific Characteristics:
  - `Nav_Command_RX` (App sends nav directions to Cane)
  - `IMU_Telemetry_TX` (Cane sends fall detection/pulse to App)
- [ ] **Task 2.2: Eye BLE Image Transfer Protocol (Dual Pipeline).** Implement the BLE 5.0 image streaming pipeline on the XIAO ESP32-S3:
  - Configure BLE Server with L2CAP CoC for high-throughput data streaming.
  - Negotiate 2M PHY and Data Length Extension on connection.
  - On button press: capture image → downscale to 640x480 → JPEG compress (~30-50 KB) → chunk into ~240-byte BLE packets with sequence numbers → stream to phone.
  - Simultaneously, run the local SenseCraft AI / TFLite Micro model and send result text over a standard BLE GATT characteristic.
  - Test end-to-end transfer time target: image fully received on phone in <1.5 seconds.
- [ ] **Task 2.3: App BLE Client MVP.** In the mobile app (React Native / Flutter / Native), implement BLE scanning and connection to the Arduino Nano ESP32. Add debug buttons to send test navigation commands and read telemetry.

### Phase 3: Mobile App Core Features (Week 3)
**Goal:** Build the independent features mapped out in `README.md`.
- [ ] **Task 3.1: Voice Command Flow.** Implement Speech-to-Text (STT) on the app. Create a state machine that listens for the wake word (if applicable), records the destination, and converts it to text.
- [ ] **Task 3.2: Mapbox SDK Integration.** Install Mapbox SDK. Create an API call that takes the STT string, gets coordinates, and generates Walking turn-by-turn directions.
- [ ] **Task 3.3: App Text-to-Speech (TTS).** Hook up native TTS to read out the Mapbox directions and confirm the required destination to the user.
- [ ] **Task 3.4: On-Device Vision Model Experimentation.** This is a research-heavy task. The goal is to find the best local phone model for rich scene descriptions:
  - Set up a test harness in the app that loads an image and passes it to a VLM.
  - Experiment with candidates: moondream2 (via MLC LLM), MiniCPM-V, Phi-3-Vision (quantized), LLaVA (4-bit), and platform-native options (Apple VisionKit on iOS, ML Kit on Android).
  - For each model, benchmark: inference time, memory usage, and description quality (does it read text? describe spatial layout? count people?).
  - Document findings and select the primary on-device model.
  - Implement a fallback path: if local model is unavailable or quality is poor, send the image to Google Gemini Vision API and use the cloud response instead.

### Phase 4: Complex Logic & Integration (Week 4)
**Goal:** Solve the Design Challenges from `iCan.md` and merge hardware with the app.
- [ ] **Task 4.1: Sweep & Obstacle Logic (Design Challenge 2).** On the Arduino, integrate IMU yaw/pitch data with Ultrasonic data. If the cane is swinging left, ignore the right sensor temporarily. Map the processed data to trigger the DRV2605L motors. Let local obstacle detection override BLE navigation signals.
- [ ] **Task 4.2: Guided Nav Haptic Rules (Design Challenge 1).** Write the firmware state machine: 
  - If `BLE_Nav == Turn Left` -> pulse left motor slowly.
  - If `Obstacle == Left` -> vibrate left motor heavily.
  - Test the prioritization matrix.
- [ ] **Task 4.3: App & Eye Dual-Pipeline Integration (Design Challenge 3).** Wire together the full end-to-end flow:
  - Button press on iCan Eye → XIAO sends instant text result (Pipeline 1) via BLE GATT → App immediately speaks basic detection via TTS.
  - Simultaneously, XIAO streams JPEG image (Pipeline 2) via BLE L2CAP → App reassembles image → App runs local VLM (selected in Task 3.4) → App speaks rich scene description via TTS.
  - If local VLM is below quality threshold, app automatically falls back to cloud Vision API.
  - Handle edge cases: BLE disconnection mid-transfer, camera failure, model timeout.
- [ ] **Task 4.4: Fall Detection & Pulse Alerts.** Process the IMU free-fall interrupt on the Arduino. Send a BLE alert to the app. Have the app sound an audio alarm and potentially hook up to an emergency SMS feature.

### Phase 5: Field Testing & Refinement (Week 5+)
- [ ] **Task 5.1:** Lab test with blindfolds to refine haptic intensity and spatial awareness of the lidar/ultrasonic zones.
- [ ] **Task 5.2:** Fine-tune Mapbox SDK GPS precision vs walking speed to ensure turns are called out via haptics at the right distance.
- [ ] **Task 5.3:** Optimize power consumption (Deep sleep for ESP32s, lowering clock speeds when idle).
