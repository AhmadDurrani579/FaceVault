//
//  FaceVaultSegmentor.cpp
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#include "FaceVaultSegmentor.hpp"
#include <opencv2/opencv.hpp>
#include <cmath>

namespace facevault {

// MARK: - Main Segment
SegmentResult FaceSegmentor::segment(const ImageBuffer& croppedFace) const {
    SegmentResult result;
    result.success = false;

    if (croppedFace.data.empty()) {
        result.error = "Empty input";
        return result;
    }
    
    ImageBuffer safeCopy = croppedFace;

    // Step 1 — BGRA to RGB
    ImageBuffer rgb = bgraToRgb(safeCopy);

    // Step 2 — GrabCut segmentation
    ImageBuffer mask = grabCutSegment(rgb);

    // Step 3 — apply mask
    ImageBuffer masked = applyMask(rgb, mask);

    // Step 4 — fill background with mean face color
    ImageBuffer filled = fillBackground(masked, mask);

    // Calculate coverage score
    int facePixels = 0;
    for (auto& v : mask.data) {
        if (v > 0) facePixels++;  // any non-zero value
    }
    result.coverageScore = static_cast<float>(facePixels) /
                           (mask.width * mask.height);

    result.segmentedFace = filled;
    result.mask          = mask;
    result.success       = true;

    printf("✅ FaceVault C++: Segmentation done — coverage: %.2f\n",
           result.coverageScore);

    return result;
}

// MARK: - BGRA to RGB
ImageBuffer FaceSegmentor::bgraToRgb(const ImageBuffer& input) const {
    cv::Mat bgra(input.height, input.width, CV_8UC4,
                 const_cast<uint8_t*>(input.data.data()));
    cv::Mat rgb;
    cv::cvtColor(bgra, rgb, cv::COLOR_BGRA2RGB);

    ImageBuffer output;
    output.width    = rgb.cols;
    output.height   = rgb.rows;
    output.channels = 3;
    output.data.assign(rgb.data, rgb.data + rgb.total() * rgb.channels());
    return output;
}

// MARK: - GrabCut
ImageBuffer FaceSegmentor::grabCutSegment(const ImageBuffer& input) const {
    cv::Mat img;
    if (input.channels == 4) {
        cv::Mat bgra(input.height, input.width, CV_8UC4,
                     const_cast<uint8_t*>(input.data.data()));
        cv::cvtColor(bgra, img, cv::COLOR_BGRA2BGR);
    } else {
        cv::Mat rgb(input.height, input.width, CV_8UC3,
                    const_cast<uint8_t*>(input.data.data()));
        cv::cvtColor(rgb, img, cv::COLOR_RGB2BGR);
    }

    // For small 160x160 face images use skin detection + ellipse mask
    // GrabCut needs larger images to work well

    // Step 1 — create ellipse mask (face shape)
    cv::Mat ellipseMask = cv::Mat::zeros(input.height, input.width, CV_8UC1);
    cv::ellipse(ellipseMask,
                cv::Point(input.width/2, input.height/2),
                cv::Size(input.width * 0.42, input.height * 0.48),
                0, 0, 360,
                cv::Scalar(255), -1);

    // Step 2 — skin color detection in HSV
    cv::Mat hsv;
    cv::cvtColor(img, hsv, cv::COLOR_BGR2HSV);
    cv::Mat skinMask;
    cv::inRange(hsv,
                cv::Scalar(0, 15, 60),    // lower skin HSV
                cv::Scalar(25, 255, 255), // upper skin HSV
                skinMask);
    
    cv::Mat skinMask2;
    cv::inRange(hsv,
                cv::Scalar(0, 10, 40),
                cv::Scalar(20, 150, 200),
                skinMask2);

    cv::bitwise_or(skinMask, skinMask2, skinMask);

    // Step 3 — combine ellipse + skin mask
    cv::Mat combined;
//    cv::bitwise_and(ellipseMask, skinMask, combined);
    cv::bitwise_and(ellipseMask, ellipseMask, combined);
    // Step 4 — morphological cleanup
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(7, 7));
    cv::morphologyEx(combined, combined, cv::MORPH_CLOSE, kernel);
    cv::morphologyEx(combined, combined, cv::MORPH_DILATE, kernel);

    int fgCount = cv::countNonZero(combined);
    printf("Segmentation fg pixels: %d / %d\n",
           fgCount, input.width * input.height);

    ImageBuffer maskOut;
    maskOut.width    = combined.cols;
    maskOut.height   = combined.rows;
    maskOut.channels = 1;
    maskOut.data.assign(combined.data,
                        combined.data + combined.total());
    return maskOut;
}


// MARK: - Apply Mask
ImageBuffer FaceSegmentor::applyMask(const ImageBuffer& input,
                                      const ImageBuffer& mask) const {
    ImageBuffer output = input;
    for (int i = 0; i < input.width * input.height; i++) {
        if (mask.data[i] == 0) {
            for (int c = 0; c < input.channels; c++) {
                output.data[i * input.channels + c] = 0;
            }
        }
    }
    return output;
}

// MARK: - Fill Background
ImageBuffer FaceSegmentor::fillBackground(const ImageBuffer& masked,
                                           const ImageBuffer& mask) const {
    // Calculate mean face color
    float sumR = 0, sumG = 0, sumB = 0;
    int count = 0;

    for (int i = 0; i < masked.width * masked.height; i++) {
        if (mask.data[i] > 0) {
            sumR += masked.data[i * masked.channels + 0];
            sumG += masked.data[i * masked.channels + 1];
            sumB += masked.data[i * masked.channels + 2];
            count++;
        }
    }

    uint8_t meanR = count > 0 ? static_cast<uint8_t>(sumR / count) : 128;
    uint8_t meanG = count > 0 ? static_cast<uint8_t>(sumG / count) : 128;
    uint8_t meanB = count > 0 ? static_cast<uint8_t>(sumB / count) : 128;

    ImageBuffer output = masked;
    for (int i = 0; i < masked.width * masked.height; i++) {
        if (mask.data[i] == 0) {
            output.data[i * masked.channels + 0] = meanR;
            output.data[i * masked.channels + 1] = meanG;
            output.data[i * masked.channels + 2] = meanB;
        }
    }

    return output;
}

} // namespace facevault
