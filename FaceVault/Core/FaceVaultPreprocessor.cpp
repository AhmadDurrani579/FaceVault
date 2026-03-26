//
//  FaceVaultPreprocessor.cpp
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#include "FaceVaultPreprocessor.hpp"
#include "FaceVaultSegmentor.hpp"
#include "FaceVaultAligner.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>
#include <opencv2/opencv.hpp>

namespace facevault {


// MARK: - Crop Face
PreprocessResult FacePreprocessor::process(const ImageBuffer& frame,
                                            const FaceRect& faceRect) const {
    PreprocessResult result;
    result.success  = false;
    result.tooFar   = false;
    result.tooClose = false;

    // Step 1 — quality check
    float quality = qualityScore(frame, faceRect);
    result.qualityScore = quality;
    if (quality < minQuality) {
        result.error = "Face quality too low";
        return result;
    }

    // Step 2 — distance check
    float ipd = ipdDistance(faceRect, frame.width);
    if (ipd < minIPD) {
        result.tooFar = true;
        result.error  = "Too far away";
        return result;
    }
    if (ipd > maxIPD) {
        result.tooClose = true;
        result.error    = "Too close";
        return result;
    }

    // Step 3 — crop face
    ImageBuffer cropped = cropFace(frame, faceRect);
    if (cropped.data.empty()) {
        result.error = "Failed to crop";
        return result;
    }

    // Step 4 — face alignment ← NEW
    FaceAligner aligner;
    AlignResult alignResult = aligner.align(
        cropped,
        faceRect.leftEyeX,  faceRect.leftEyeY,
        faceRect.rightEyeX, faceRect.rightEyeY
    );

    ImageBuffer toSegment = alignResult.success ?
                            alignResult.alignedFace :
                            resize(cropped, targetSize, targetSize);

    if (alignResult.success) {
        printf("✅ FaceVault C++: Aligned — angle:%.2f\n", alignResult.rollAngle);
    } else {
        printf("⚠️ FaceVault C++: Alignment failed — %s\n", alignResult.error.c_str());
        // Fallback — resize without alignment
        toSegment = resize(cropped, targetSize, targetSize);
    }
    
    // Step 4.5 — Retinex illumination normalization
    ImageBuffer illuminated = retinexNormalize(toSegment);
    ImageBuffer toSegmentFinal = illuminated.data.empty() ? toSegment : illuminated;

    // Step 5 — segmentation
    FaceSegmentor segmentor;
    SegmentResult segResult = segmentor.segment(toSegmentFinal);
    ImageBuffer toNormalize = segResult.success ?
                              segResult.segmentedFace : toSegmentFinal;

    // Step 6 — normalize
    ImageBuffer normalized = normalize(toNormalize);

    result.croppedFace = normalized;
    result.success     = true;
    return result;
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


ImageBuffer FacePreprocessor::cropFace(const ImageBuffer& frame,
                                        const FaceRect& faceRect) const {
    // Add 20% padding
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

    // Convert to pixel coords
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

    // Crop pixels
    ImageBuffer cropped;
    cropped.width    = w;
    cropped.height   = h;
    cropped.channels = frame.channels;
    cropped.data.resize(w * h * frame.channels);

    for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
            int srcIdx = ((y0 + row) * frame.width + (x0 + col)) * frame.channels;
            int dstIdx = (row * w + col) * frame.channels;
            for (int c = 0; c < frame.channels; c++) {
                cropped.data[dstIdx + c] = frame.data[srcIdx + c];
            }
        }
    }

    return cropped;
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

float FacePreprocessor::ipdDistance(const FaceRect& faceRect,
                                     int frameWidth) const {
    // Calculate pixel distance between eyes
    float dx = (faceRect.rightEyeX - faceRect.leftEyeX) * frameWidth;
    float dy = (faceRect.rightEyeY - faceRect.leftEyeY) * frameWidth;
    float ipdPixels = std::sqrt(dx * dx + dy * dy);
    
    printf("IPD pixels: %.1f frameWidth: %d\n", ipdPixels, frameWidth);
    
    return ipdPixels;
}

// MARK: - Retinex Illumination Normalization
ImageBuffer FacePreprocessor::retinexNormalize(const ImageBuffer& input) const {
    if (input.data.empty()) return input;

    cv::Mat img;
    if (input.channels == 4) {
        cv::Mat bgra(input.height, input.width, CV_8UC4,
                     const_cast<uint8_t*>(input.data.data()));
        cv::cvtColor(bgra, img, cv::COLOR_BGRA2BGR);
    } else {
        img = cv::Mat(input.height, input.width, CV_8UC3,
                      const_cast<uint8_t*>(input.data.data())).clone();
    }

    // Convert to float
    cv::Mat imgFloat;
    img.convertTo(imgFloat, CV_32F);
    imgFloat += 1.0f; // avoid log(0)

    // Single Scale Retinex per channel
    cv::Mat result = cv::Mat::zeros(imgFloat.size(), imgFloat.type());
    std::vector<cv::Mat> channels(3);
    cv::split(imgFloat, channels);

    float sigma = 30.0f; // scale — smaller = more detail

    for (int c = 0; c < 3; c++) {
        cv::Mat blurred;
        cv::GaussianBlur(channels[c], blurred,
                         cv::Size(0, 0), sigma);
        blurred += 1.0f;

        cv::Mat retinex;
        cv::log(channels[c], retinex);
        cv::Mat logBlur;
        cv::log(blurred, logBlur);
        retinex -= logBlur;

        // Normalize to 0-255
        double minVal, maxVal;
        cv::minMaxLoc(retinex, &minVal, &maxVal);
        retinex = (retinex - minVal) / (maxVal - minVal + 1e-6f) * 255.0f;
        retinex.convertTo(channels[c], CV_8U);
    }

    cv::Mat output;
    cv::merge(channels, output);

    printf("✅ FaceVault C++: Retinex normalization applied\n");

    // Convert back to ImageBuffer
    ImageBuffer result2;
    result2.width    = output.cols;
    result2.height   = output.rows;
    result2.channels = 3;
    result2.data.assign(output.data,
                        output.data + output.total() * output.channels());
    return result2;
}

} // namespace facevault
