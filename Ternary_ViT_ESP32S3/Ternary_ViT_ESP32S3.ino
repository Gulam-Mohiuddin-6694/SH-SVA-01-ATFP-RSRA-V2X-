/**
 * @file ternary_vit_esp32s3.cpp
 * @brief Implementation of a Ternary Vision Transformer inference engine optimized for ESP32-S3 (N16R8).
 * 
 * Features:
 * - Uses PSRAM (ESP_MALLOC_CAP_SPIRAM) for storing large feature maps and weights.
 * - Ternary Weights (-1, 0, +1) packed efficiently (2 bits per weight).
 * - Replaces multiply-accumulate (MAC) with simple add/sub operations for ternary layers.
 * 
 * Note: This code provides the inference architecture. You must train a Ternary ViT 
 * (e.g., using PyTorch with QAT), extract the ternary weights, pack them, and load 
 * them onto the ESP32's flash (SPIFFS/LittleFS) or embed them as const arrays.
 */

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <math.h>

// --- ViT Configuration (Tiny/Custom Variant for Edge) ---
const int IMAGE_SIZE = 96;       // Input image size (96x96)
const int CHANNELS = 3;          // RGB
const int PATCH_SIZE = 16;       // Patch size (16x16)
const int NUM_PATCHES = (IMAGE_SIZE / PATCH_SIZE) * (IMAGE_SIZE / PATCH_SIZE); // 36
const int EMBED_DIM = 192;       // Embedding dimension
const int NUM_HEADS = 3;         // Number of attention heads
const int MLP_DIM = 768;         // Hidden dimension of MLP
const int NUM_LAYERS = 4;        // Number of transformer blocks
const int NUM_CLASSES = 10;      // Output classes

const int SEQ_LENGTH = NUM_PATCHES + 1; // +1 for CLS token (37)

// Helper to allocate in PSRAM (crucial for ESP32-S3 N16R8)
float* allocatePSRAMFloat(size_t elements) {
    float* ptr = (float*)heap_caps_malloc(elements * sizeof(float), MALLOC_CAP_SPIRAM);
    if (!ptr) {
        Serial.println("ERR: Failed to allocate PSRAM!");
        while(1);
    }
    return ptr;
}

// GELU Activation Approximation (common in ViT)
inline float gelu(float x) {
    return 0.5f * x * (1.0f + tanhf(0.7978845608f * (x + 0.044715f * x * x * x)));
}

/**
 * @brief Performs Matrix Multiplication where weights are Ternary (-1, 0, 1).
 * 
 * This is the core optimization. Instead of floats, weights are logically -1, 0, or 1.
 * We bypass floating point multiplication and use additions/subtractions.
 * 
 * @param input Input vector/matrix (float)
 * @param ternary_weights Packed ternary weights (conceptually 2-bits per weight)
 * @param output Output vector/matrix (float)
 * @param in_features Number of input features
 * @param out_features Number of output features
 */
void linear_ternary(const float* input, const int8_t* ternary_weights, float* output, int in_features, int out_features) {
    // In a fully optimized version, ternary_weights would be packed bytes.
    // For readability, we assume an array of int8_t containing -1, 0, 1.
    
    for (int o = 0; o < out_features; o++) {
        float sum = 0.0f;
        int weight_idx = o * in_features;
        
        for (int i = 0; i < in_features; i++) {
            int8_t w = ternary_weights[weight_idx + i];
            
            // Ternary Optimization: No multiplication!
            if (w == 1) {
                sum += input[i];
            } else if (w == -1) {
                sum -= input[i];
            }
            // If w == 0, do nothing.
        }
        output[o] = sum;
    }
}

// Standard Float Linear layer (used for initial patch embedding and final classifier)
void linear_float(const float* input, const float* weights, const float* bias, float* output, int in_features, int out_features) {
    for (int o = 0; o < out_features; o++) {
        float sum = (bias != nullptr) ? bias[o] : 0.0f;
        int weight_idx = o * in_features;
        for (int i = 0; i < in_features; i++) {
            sum += input[i] * weights[weight_idx + i];
        }
        output[o] = sum;
    }
}

// Layer Normalization
void layer_norm(float* data, const float* gamma, const float* beta, int seq_len, int embed_dim) {
    for (int s = 0; s < seq_len; s++) {
        float mean = 0.0f;
        float var = 0.0f;
        int offset = s * embed_dim;
        
        for (int i = 0; i < embed_dim; i++) mean += data[offset + i];
        mean /= embed_dim;
        
        for (int i = 0; i < embed_dim; i++) {
            float diff = data[offset + i] - mean;
            var += diff * diff;
        }
        var /= embed_dim;
        
        float inv_std = 1.0f / sqrtf(var + 1e-5f);
        
        for (int i = 0; i < embed_dim; i++) {
            float norm_val = (data[offset + i] - mean) * inv_std;
            data[offset + i] = norm_val * gamma[i] + beta[i];
        }
    }
}

// Ternary Multi-Head Self-Attention
void ternary_msa(const float* input, float* output, 
                 const int8_t* w_qkv, const int8_t* w_proj, 
                 float* buffer_qkv) {
    
    // 1. Calculate Q, K, V simultaneously using Ternary Linear
    // input shape: (SEQ_LENGTH, EMBED_DIM)
    // w_qkv shape: (3 * EMBED_DIM, EMBED_DIM) -> Ternary
    // buffer_qkv shape: (SEQ_LENGTH, 3 * EMBED_DIM)
    
    for(int s=0; s < SEQ_LENGTH; s++) {
        linear_ternary(&input[s * EMBED_DIM], w_qkv, &buffer_qkv[s * 3 * EMBED_DIM], EMBED_DIM, 3 * EMBED_DIM);
    }

    // 2. Attention mechanism (Float operations required for Softmax)
    int head_dim = EMBED_DIM / NUM_HEADS;
    float scale = 1.0f / sqrtf(head_dim);
    
    // Allocate temporary buffers in PSRAM for attention scores
    float* att_scores = allocatePSRAMFloat(SEQ_LENGTH * SEQ_LENGTH);
    
    for (int h = 0; h < NUM_HEADS; h++) {
        // Compute Q * K^T
        for (int i = 0; i < SEQ_LENGTH; i++) {
            for (int j = 0; j < SEQ_LENGTH; j++) {
                float sum = 0.0f;
                for (int d = 0; d < head_dim; d++) {
                    float q = buffer_qkv[i * 3 * EMBED_DIM + (h * head_dim) + d];
                    // K is located after Q (offset by EMBED_DIM)
                    float k = buffer_qkv[j * 3 * EMBED_DIM + EMBED_DIM + (h * head_dim) + d];
                    sum += q * k;
                }
                att_scores[i * SEQ_LENGTH + j] = sum * scale;
            }
        }
        
        // Softmax over rows
        for (int i = 0; i < SEQ_LENGTH; i++) {
            float max_val = -1e9;
            for (int j = 0; j < SEQ_LENGTH; j++) {
                if (att_scores[i * SEQ_LENGTH + j] > max_val) max_val = att_scores[i * SEQ_LENGTH + j];
            }
            float sum = 0.0f;
            for (int j = 0; j < SEQ_LENGTH; j++) {
                att_scores[i * SEQ_LENGTH + j] = expf(att_scores[i * SEQ_LENGTH + j] - max_val);
                sum += att_scores[i * SEQ_LENGTH + j];
            }
            for (int j = 0; j < SEQ_LENGTH; j++) {
                att_scores[i * SEQ_LENGTH + j] /= sum;
            }
        }
        
        // Multiply by V
        for (int i = 0; i < SEQ_LENGTH; i++) {
            for (int d = 0; d < head_dim; d++) {
                float sum = 0.0f;
                for (int j = 0; j < SEQ_LENGTH; j++) {
                    // V is located after K (offset by 2*EMBED_DIM)
                    float v = buffer_qkv[j * 3 * EMBED_DIM + 2 * EMBED_DIM + (h * head_dim) + d];
                    sum += att_scores[i * SEQ_LENGTH + j] * v;
                }
                // Store temporarily back into V's position or a separate out buffer
                output[i * EMBED_DIM + (h * head_dim) + d] = sum; 
            }
        }
    }
    heap_caps_free(att_scores);

    // 3. Final projection using Ternary Linear
    float* proj_out = allocatePSRAMFloat(SEQ_LENGTH * EMBED_DIM);
    for(int s=0; s < SEQ_LENGTH; s++) {
        linear_ternary(&output[s * EMBED_DIM], w_proj, &proj_out[s * EMBED_DIM], EMBED_DIM, EMBED_DIM);
    }
    
    // Copy back
    memcpy(output, proj_out, SEQ_LENGTH * EMBED_DIM * sizeof(float));
    heap_caps_free(proj_out);
}

// Ternary MLP Block
void ternary_mlp(const float* input, float* output, 
                 const int8_t* w_fc1, const int8_t* w_fc2, 
                 float* buffer_mlp) {
    
    for(int s = 0; s < SEQ_LENGTH; s++) {
        // 1. FC1 (Ternary) -> (EMBED_DIM -> MLP_DIM)
        linear_ternary(&input[s * EMBED_DIM], w_fc1, &buffer_mlp[s * MLP_DIM], EMBED_DIM, MLP_DIM);
        
        // 2. GELU Activation
        for(int i=0; i < MLP_DIM; i++) {
            buffer_mlp[s * MLP_DIM + i] = gelu(buffer_mlp[s * MLP_DIM + i]);
        }
        
        // 3. FC2 (Ternary) -> (MLP_DIM -> EMBED_DIM)
        linear_ternary(&buffer_mlp[s * MLP_DIM], w_fc2, &output[s * EMBED_DIM], MLP_DIM, EMBED_DIM);
    }
}

// Dummy Weights (In reality, load these from Flash/PSRAM)
float* patch_embed_weights; // (EMBED_DIM, CHANNELS * PATCH_SIZE * PATCH_SIZE) - Float
float* pos_embedding;       // (SEQ_LENGTH, EMBED_DIM) - Float
float* cls_token;           // (1, EMBED_DIM) - Float

// Ternary Layer Weights (Pointers to int8_t arrays)
int8_t* t_w_qkv[NUM_LAYERS];
int8_t* t_w_proj[NUM_LAYERS];
int8_t* t_w_mlp_fc1[NUM_LAYERS];
int8_t* t_w_mlp_fc2[NUM_LAYERS];

// Layer Norm parameters
float* ln_gamma_1[NUM_LAYERS];
float* ln_beta_1[NUM_LAYERS];
float* ln_gamma_2[NUM_LAYERS];
float* ln_beta_2[NUM_LAYERS];

float* classifier_weights; // (NUM_CLASSES, EMBED_DIM) - Float
float* classifier_bias;    // (NUM_CLASSES) - Float

void run_ternary_vit_inference(const float* image_data) {
    Serial.println("--- Starting Ternary ViT Inference ---");
    unsigned long start_time = millis();

    // 1. Allocate Main Working Memory in PSRAM
    float* x = allocatePSRAMFloat(SEQ_LENGTH * EMBED_DIM);
    float* x_norm = allocatePSRAMFloat(SEQ_LENGTH * EMBED_DIM);
    float* buffer_qkv = allocatePSRAMFloat(SEQ_LENGTH * 3 * EMBED_DIM);
    float* buffer_mlp = allocatePSRAMFloat(SEQ_LENGTH * MLP_DIM);
    
    // 2. Patch Embedding (Float)
    // Flatten patches and project. (Omitted exact patching logic for brevity; 
    // assuming image_data is pre-patched or linear_float handles the mapping).
    // ... [Patch Projection Code] ...

    // Add CLS token and Position Embeddings
    // ... [Add Embeddings Code] ...

    // 3. Transformer Blocks
    for (int l = 0; l < NUM_LAYERS; l++) {
        // Layer Norm 1
        memcpy(x_norm, x, SEQ_LENGTH * EMBED_DIM * sizeof(float));
        layer_norm(x_norm, ln_gamma_1[l], ln_beta_1[l], SEQ_LENGTH, EMBED_DIM);
        
        // Ternary MSA
        ternary_msa(x_norm, x_norm, t_w_qkv[l], t_w_proj[l], buffer_qkv);
        
        // Residual Connection 1
        for (int i = 0; i < SEQ_LENGTH * EMBED_DIM; i++) x[i] += x_norm[i];

        // Layer Norm 2
        memcpy(x_norm, x, SEQ_LENGTH * EMBED_DIM * sizeof(float));
        layer_norm(x_norm, ln_gamma_2[l], ln_beta_2[l], SEQ_LENGTH, EMBED_DIM);

        // Ternary MLP
        ternary_mlp(x_norm, x_norm, t_w_mlp_fc1[l], t_w_mlp_fc2[l], buffer_mlp);

        // Residual Connection 2
        for (int i = 0; i < SEQ_LENGTH * EMBED_DIM; i++) x[i] += x_norm[i];
    }

    // 4. Classification Head
    float* cls_output = &x[0]; // First token is CLS
    float logits[NUM_CLASSES];
    
    linear_float(cls_output, classifier_weights, classifier_bias, logits, EMBED_DIM, NUM_CLASSES);

    // 5. Output Result
    int best_class = 0;
    float max_logit = logits[0];
    for (int i = 1; i < NUM_CLASSES; i++) {
        if (logits[i] > max_logit) {
            max_logit = logits[i];
            best_class = i;
        }
    }

    unsigned long end_time = millis();
    Serial.printf("Inference complete in %lu ms. Predicted Class: %d\n", (end_time - start_time), best_class);

    // Free PSRAM
    heap_caps_free(x);
    heap_caps_free(x_norm);
    heap_caps_free(buffer_qkv);
    heap_caps_free(buffer_mlp);
}

void setup() {
    Serial.begin(115200);
    while(!Serial) delay(10);
    
    Serial.println("\n--- ESP32-S3 (N16R8) Ternary ViT Initializing ---");
    
    // Verify PSRAM is available
    if (psramInit()) {
        Serial.printf("PSRAM initialized. Total: %d bytes, Free: %d bytes\n", 
                      ESP.getPsramSize(), ESP.getFreePsram());
    } else {
        Serial.println("ERR: PSRAM not found! N16R8 requires PSRAM.");
        while(1);
    }

    // In a real scenario, you would allocate and load the ternary weights
    // from a filesystem (SPIFFS/SD Card) into PSRAM here.
    // e.g., t_w_qkv[0] = (int8_t*)heap_caps_malloc(size, MALLOC_CAP_SPIRAM);
    
    Serial.println("Setup complete. Ready for inference.");
}

void loop() {
    // Dummy image data
    float* dummy_image = allocatePSRAMFloat(IMAGE_SIZE * IMAGE_SIZE * CHANNELS);
    // ... Fill dummy image with camera data ...
    
    // run_ternary_vit_inference(dummy_image);
    
    heap_caps_free(dummy_image);
    delay(5000); // Run inference every 5 seconds
}
