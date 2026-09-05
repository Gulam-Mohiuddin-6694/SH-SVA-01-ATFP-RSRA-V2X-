# ESP32 Advanced AI and Post-Quantum Security Projects

This repository contains conceptual implementations for two advanced projects targeting the ESP32 ecosystem, specifically pushing the boundaries of edge AI and future-proof secure communications.

---

## 1. Ternary Vision Transformer (ViT) on ESP32-S3 (N16R8)

This project demonstrates how to run a Vision Transformer on an edge device by utilizing Ternary Quantization (-1, 0, 1) and leveraging the ESP32-S3's PSRAM.

**File:** `ternary_vit_esp32s3.cpp`

### Key Features
* **PSRAM Utilization:** Specifically targets the ESP32-S3 N16R8 (16MB Flash, 8MB PSRAM). Large feature maps and attention matrices are explicitly allocated in PSRAM using `heap_caps_malloc`.
* **Ternary Weights (-1, 0, +1):** Dramatically reduces the memory footprint of model weights.
* **Multiplier-Free Linear Layers:** Replaces expensive floating-point multiply-accumulate (MAC) operations with simple additions and subtractions, significantly speeding up inference on microcontrollers.

### How it Works
The code replaces standard Matrix Multiplication (Dense/Linear layers) with a specialized `linear_ternary` function. Instead of multiplying an input activation by a float weight, it checks the ternary weight state (1, -1, or 0) and simply adds or subtracts the input value from the accumulator.

### Implementation Steps
* **Training:** You must train a ViT model off-device (e.g., in PyTorch) using Quantization-Aware Training (QAT) to constrain the weights to -1, 0, 1.
* **Export:** Extract the quantized weights, pack them efficiently (e.g., 2 bits per weight), and store them as C-arrays or load them onto the ESP32's SPIFFS/LittleFS.
* **Hardware Requirements:** An ESP32-S3 with PSRAM is mandatory. Internal SRAM (usually ~512KB) is insufficient for Transformer sequence lengths and hidden dimensions.

---

## 2. Post-Quantum (ML-KEM-512) Communication Protocol for ESP32

This project outlines a custom communication protocol similar to ESP-NOW, but secured using the NIST-standardized Post-Quantum Key Encapsulation Mechanism, ML-KEM-512 (formerly Kyber512).

**File:** `pq_esp_protocol.cpp`

### Key Features
* **Quantum-Resistant:** Utilizes lattice-based cryptography designed to resist attacks from future quantum computers.
* **Key Encapsulation Flow:** Demonstrates the correct sequence: Key Generation -> Public Key Exchange -> Shared Secret Encapsulation -> Ciphertext Exchange -> Decapsulation.
* **Symmetric Encryption:** Once the shared secret is established via ML-KEM, standard AES-256-GCM is used for encrypting the actual payload data.

### Protocol Flow
1. **Node A (Initiator):** Generates an ML-KEM Keypair and sends the Public Key (800 bytes) to Node B.
2. **Node B (Responder):** Receives the Public Key, runs the Encapsulation algorithm to generate a Shared Secret and a Ciphertext (768 bytes), and sends the Ciphertext back to Node A.
3. **Node A:** Receives the Ciphertext, runs Decapsulation using its Secret Key, and derives the same Shared Secret.
4. **Both Nodes:** Can now communicate symmetrically using AES-GCM keyed with the Shared Secret.

### Implementation Notes & Limitations
* **Fragmentation Required:** Standard ESP-NOW has a payload limit of 250 bytes. ML-KEM-512 keys and ciphertexts exceed 700 bytes. To implement this over raw ESP-NOW, you must write a fragmentation and reassembly layer to send the keys in multiple chunks. Alternatively, use standard UDP/TCP over WiFi where MTU/fragmentation is handled by the stack.
* **Mock Functions:** The provided code uses mock functions for the heavy cryptographic operations. You must link a lightweight C implementation of ML-KEM (Kyber) and AES-GCM (e.g., mbedTLS) compiled for the Xtensa architecture.
* **Performance:** Generating and encapsulating ML-KEM keys will take noticeable CPU time on an ESP32 (tens to hundreds of milliseconds) compared to standard ECC.

---

## Getting Started

Both files are Arduino IDE compatible but are designed to be used within the Espressif IoT Development Framework (ESP-IDF) or PlatformIO for better memory and build control.

* Ensure you have the ESP32 board manager installed.
* For the ViT project, ensure your board settings have PSRAM enabled (e.g., "OPI PSRAM").
