# ML Testing & Evaluation Environment

This directory is dedicated to the testing, comparison, and evaluation of Computer Vision (CV) / Machine Learning (ML) models for the **iCan Eye** module.

## Purpose

The primary goal here is to determine the most optimal object detection model before integrating it into the production codebase. You can use this space to compare running models locally (on a microcontroller) versus on a mobile device (smartphone).

## Optimal Setup Recommendation: Smartphone Processing

Based on the [iCan.md](../iCan.md) and [README.md](../README.md) specifications, **offloading the image processing to the user's smartphone is the highly recommended and optimal approach.**

### Why?
1. **Computational Power**: Modern smartphones have dedicated NPUs (Neural Processing Units) and vastly superior CPUs/GPUs compared to the XIAO ESP32-S3. They can run much larger, more accurate models (like YOLOv8-lite, MobileNet SSD) in real-time.
2. **Speed & Latency**: Running complex object detection on an ESP32 can yield very low frames-per-second (FPS) and high latency. A phone will provide near-instantaneous feedback, which is critical for a visually impaired user navigating their environment.
3. **Ecosystem & Libraries**: Mobile platforms have robust ML frameworks like TensorFlow Lite and PyTorch Mobile, as well as native APIs (CoreML for iOS, NNAPI for Android) optimized for vision tasks.
4. **Power Consumption**: While transmitting images via BLE/Wi-Fi to the phone consumes power on the ESP32, running heavy ML inferences locally on the microcontroller drains the iCan Eye's small 1200mAh battery drastically faster.

### The Proposed Architecture
- **iCan Eye (XIAO ESP32-S3)**: Acts as a wireless camera. It captures the image/video frame when the button is pressed (or continuously) and sends the JPEG payload over BLE (or WiFi for higher bandwidth) to the app.
- **iCan App (Flutter/Smartphone)**: Receives the frame, runs it through the local TensorFlow Lite or OpenCV object detection model, formats the results into a descriptive sentence, and uses Text-to-Speech (TTS) to output the audio to the user.

## Structure of this Folder

You can organize this testing environment as follows:
- `datasets/`: Store test images representing real-world scenarios a visually impaired person might encounter.
- `models/`: Store your `.tflite`, `.onnx`, or PyTorch models here.
- `scripts/`: Python scripts for evaluating model accuracy, inference time, and memory footprint.
- `esp32_test/`: (Optional) Minimal C++ sketches to test microcontroller inference limitations, if you want to benchmark it directly against the phone.

## Getting Started

1. Collect sample images.
2. Write a Python script to run inference on those images using different TFLite models.
3. Measure the inference time and accuracy for each, then select the best one to bundle into the Flutter app's `assets/` folder constraint.
