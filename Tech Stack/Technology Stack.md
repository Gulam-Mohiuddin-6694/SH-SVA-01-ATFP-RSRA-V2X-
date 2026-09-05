# Technology Stack Overview

Based on the architecture detailed in **image_f3d4bd.jpg**, the system's technology stack is divided into two primary domains: edge hardware operations and central cloud/server control. Below is a high-level overview of the languages, frameworks, and tools utilized across the platform.

---

## 1. Edge Intelligent Sensing Nodes
This stack powers the field devices (targeting hardware like ESP32-S3, STM32N6, and Ambarella CV75A), focusing on real-time device control, local AI processing, and secure transmission.

*   **Embedded Programming & Firmware**
    *   **Languages:** C, C++
    *   **Key Libraries & RTOS:** ESP-IDF, STM32CubeHAL, AmbaHAL (Linux SDK), FreeRTOS
*   **Edge AI & Feature Extraction**
    *   **Core Model:** FterVit (FasterViT) via ONNX interchange
    *   **Languages:** C++, Python (for training and model conversion)
    *   **Key Libraries:** TensorFlow Lite for Microcontrollers (TFLM), Edge Impulse (TinyEngine), X-CUBE-AI, ONNX Runtime
*   **Post-Quantum Cryptography (PQC)**
    *   **Standard:** NIST ML-KEM 512 (KYBER)
    *   **Key Libraries:** CRYSTALS-Kyber C/C++ Libraries, embedded wolfSSL or OpenSSL 3.x with PQC support

---

## 2. Agentic Multi-Modal Control Hub
This stack drives the central backend, handling complex coordination, advanced AI explainability, and user-facing dashboards.

*   **Central Backend & Agentic Logic**
    *   **Languages:** Python (3.10+), Go (for Middleware), Rust (for Secure Networking)
    *   **Key Libraries:** FastAPI, Flask, Ray, LangChain, PyAgentic
    *   **Neuro-Symbolic Rules:** Python State Machines, Custom Rule Engines
*   **Central AI & Explainability Layer**
    *   **Languages:** Python
    *   **Model Serving:** PyTorch, TensorFlow
    *   **Explainability Core:** SHAP (Shapley Additive exPlanations), LIME (Local Interpretable Model-agnostic Explanations)
*   **Data Integration & Human-Machine Interface (HMI)**
    *   **Languages:** Python, JavaScript, CSS, HTML5
    *   **Frontend Libraries:** React, Vue.js, D3.js (for data visualization)
    *   **Data Brokerage:** MQTT Brokers (e.g., EMQX, HiveMQ)

<img width="1450" height="600" alt="image" src="https://github.com/user-attachments/assets/adeee256-7274-48e6-89b2-4da8776bac14" />
