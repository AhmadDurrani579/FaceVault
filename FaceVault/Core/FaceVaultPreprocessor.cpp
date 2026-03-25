//
//  FaceVaultPreprocessor.cpp
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#include "FaceVaultPreprocessor.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>

namespace facevault {
PreprocessResult FacePreprocessor::process(const ImageBuffer& frame,
                                           const FaceRect& faceRect) const {
    PreprocessResult result;
    result.success = false;
    
    // Step 1 — quality check first

    float quality = qualityScore(frame, faceRect);
    result.qualityScore = quality;
    
    if (quality < minQuality) {
        result.error = "Face quality too low: " + std::to_string(quality);
        return result;
    }
    
    // Step 2 — crop face
    ImageBuffer cropped = cropFace(frame, faceRect);
    if (cropped.data.empty()) {
        result.error = "Failed to crop face";
        return result;
    }
    
    // Step 3 — resize to 160x160
    ImageBuffer resized = resize(cropped, targetSize, targetSize);
    if (resized.data.empty()) {
        result.error = "Failed to resize face";
        return result;
    }

    // Step 4 — normalize
    ImageBuffer normalized = normalize(resized);

    result.croppedFace = normalized;
    result.success = true;
    return result;
    
}

// MARK: - Crop Face
ImageBuffer FacePreprocessor::cropFace(const ImageBuffer& frame,
                                        const FaceRect& faceRect) const {
    // Add 20% padding around face
    float padding = 0.20f;
    float px = faceRect.x - (faceRect.width  * padding);
    float py = faceRect.y - (faceRect.height * padding);
    float pw = faceRect.width  * (1.0f + 2.0f * padding);
    float ph = faceRect.height * (1.0f + 2.0f * padding);

    // Clamp to frame bounds
    px = std::max(0.0f, px);
    py = std::max(0.0f, py);
    pw = std::min(1.0f - px, pw);
    ph = std::min(1.0f - py, ph);

    // Convert normalized to pixel coords
    int x0 = static_cast<int>(px * frame.width);
    int y0 = static_cast<int>(py * frame.height);
    int w  = static_cast<int>(pw * frame.width);
    int h  = static_cast<int>(ph * frame.height);

    // Clamp
    x0 = std::max(0, std::min(x0, frame.width  - 1));
    y0 = std::max(0, std::min(y0, frame.height - 1));
    w  = std::min(w, frame.width  - x0);
    h  = std::min(h, frame.height - y0);

    if (w <= 0 || h <= 0) return {};

    // Crop
    ImageBuffer cropped;
    cropped.width    = w;
    cropped.height   = h;
    cropped.channels = frame.channels;
    cropped.data.resize(w * h * frame.channels);

    for (int row = 0; row < h; row++) {
        int srcRow = y0 + row;
        for (int col = 0; col < w; col++) {
            int srcCol = x0 + col;
            int srcIdx = (srcRow * frame.width + srcCol) * frame.channels;
            int dstIdx = (row * w + col) * frame.channels;
            for (int c = 0; c < frame.channels; c++) {
                cropped.data[dstIdx + c] = frame.data[srcIdx + c];
            }
        }
    }

    return cropped;
}

// MARK: - Resize (bilinear interpolation)
ImageBuffer FacePreprocessor::resize(const ImageBuffer& input,
                                      int targetWidth,
                                      int targetHeight) const {
    ImageBuffer output;
    output.width    = targetWidth;
    output.height   = targetHeight;
    output.channels = input.channels;
    output.data.resize(targetWidth * targetHeight * input.channels);

    float scaleX = static_cast<float>(input.width)  / targetWidth;
    float scaleY = static_cast<float>(input.height) / targetHeight;

    for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
            float srcX = x * scaleX;
            float srcY = y * scaleY;

            int x0 = static_cast<int>(srcX);
            int y0 = static_cast<int>(srcY);
            int x1 = std::min(x0 + 1, input.width  - 1);
            int y1 = std::min(y0 + 1, input.height - 1);

            float dx = srcX - x0;
            float dy = srcY - y0;

            int dstIdx = (y * targetWidth + x) * input.channels;

            for (int c = 0; c < input.channels; c++) {
                float v00 = input.data[(y0 * input.width + x0) * input.channels + c];
                float v10 = input.data[(y0 * input.width + x1) * input.channels + c];
                float v01 = input.data[(y1 * input.width + x0) * input.channels + c];
                float v11 = input.data[(y1 * input.width + x1) * input.channels + c];

                float v = v00 * (1-dx) * (1-dy)
                        + v10 * dx     * (1-dy)
                        + v01 * (1-dx) * dy
                        + v11 * dx     * dy;

                output.data[dstIdx + c] = static_cast<uint8_t>(std::min(255.0f, v));
            }
        }
    }

    return output;
}

// MARK: - Normalize
ImageBuffer FacePreprocessor::normalize(const ImageBuffer& input) const {
    ImageBuffer output = input;

    // Calculate mean and std per channel
    for (int c = 0; c < input.channels; c++) {
        float sum = 0.0f;
        int count = input.width * input.height;

        for (int i = 0; i < count; i++) {
            sum += input.data[i * input.channels + c];
        }

        float mean = sum / count;

        float varSum = 0.0f;
        for (int i = 0; i < count; i++) {
            float diff = input.data[i * input.channels + c] - mean;
            varSum += diff * diff;
        }

        float stdDev = std::sqrt(varSum / count) + 1e-6f;

        // Normalize and clamp to 0-255
        for (int i = 0; i < count; i++) {
            float val = (input.data[i * input.channels + c] - mean) / stdDev;
            val = (val + 3.0f) / 6.0f * 255.0f; // scale to 0-255
            output.data[i * input.channels + c] = static_cast<uint8_t>(
                std::max(0.0f, std::min(255.0f, val))
            );
        }
    }

    return output;
}

// MARK: - Quality Score
float FacePreprocessor::qualityScore(const ImageBuffer& frame,
                                      const FaceRect& faceRect) const {
    float score = 1.0f;

    // Penalize head rotation
    score -= std::abs(faceRect.yaw)   * 0.5f;
    score -= std::abs(faceRect.pitch) * 0.5f;
    score -= std::abs(faceRect.roll)  * 0.3f;

    // Penalize small face
    float faceArea = faceRect.width * faceRect.height;
    if (faceArea < 0.05f) score -= 0.3f;

    // Penalize missing landmarks
    if (faceRect.landmarkCount < 50) score -= 0.3f;

    return std::max(0.0f, std::min(1.0f, score));
}

} // namespace facevault
