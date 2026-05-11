//
//  FaceVaultLivenessV4.cpp
//  FaceVault
//
//  Created by Ahmad on 25/04/2026.
//

#include "FaceVaultLivenessV4.hpp"
#include <opencv2/opencv.hpp>

namespace FaceVault {

FaceVaultLivenessV4::FaceVaultLivenessV4() {
    _rppg.setBufferSize(600);
}

void FaceVaultLivenessV4::processFrame(
    const cv::Mat& irFrame,
    double timestamp,
    float fps) {
//    if (_evaluated) return;
    // Feed frame into rPPG processor
    _fps = fps;
    _lastFrame = irFrame.clone(); // ← store latest frame
    _rppg.processFrame(irFrame, timestamp);
}

bool FaceVaultLivenessV4::hasEnoughData() const {
    // Use internal scan duration instead of signal timestamps
    return _rppg.scanDuration() >= 9.0;
}

LivenessV4Result FaceVaultLivenessV4::evaluate() {
//    _evaluated = true;
    LivenessV4Result result;
    result.isLive = false;
    result.pulseDetected = false;
    result.screenDetected = false;
    result.confidence = 0.0f;

    double duration = _rppg.scanDuration();
    if (duration < 5.0) {
        result.rejectReason = "Insufficient data";
        return result;
    }

    // Lock 3 — FFT screen detection
    // Run on latest frame
    if (!_lastFrame.empty()) {
        bool screenDetected = checkMoirePattern(_lastFrame);
        if (screenDetected) {
            result.screenDetected = true;
            result.rejectReason = "Screen detected";
            printf("[FaceVault] Lock 3 — screen detected!\n");
            return result;
        }
    }

    // Lock 1 — biological pulse
    rPPGSignal signal = _rppg.getSignal();
    if (signal.chrom.size() < 30) {
        result.rejectReason = "Signal too short";
        return result;
    }

    SignalResult signalResult = _signal.processRPPG(
        signal.chrom, _fps
    );

    result.heartRateBPM = signalResult.heartRate.bpm;

    if (checkBiologicalPulse(signalResult)) {
        result.pulseDetected = true;
        result.isLive = true;
        result.confidence = signalResult.heartRate.confidence;
    } else {
        result.rejectReason = "No biological pulse";
    }

    return result;
}

double FaceVaultLivenessV4::scanDuration() const {
    return _rppg.scanDuration();
}


bool FaceVaultLivenessV4::checkBiologicalPulse(
    const SignalResult& result) {

    if (!result.heartRate.isValid) {
        printf("[FaceVault] rPPG — rejected: invalid signal\n");
        return false;
    }
    if (result.heartRate.bpm < 40.0f) {
        printf("[FaceVault] rPPG — rejected: BPM too low (%.1f)\n",
               result.heartRate.bpm);
        return false;
    }
    if (result.heartRate.bpm > 180.0f) {
        printf("[FaceVault] rPPG — rejected: BPM too high (%.1f)\n",
               result.heartRate.bpm);
        return false;
    }
    if (result.heartRate.confidence < 0.01f) {
        printf("[FaceVault] rPPG — rejected: low confidence (%.2f)\n",
               result.heartRate.confidence);
        return false;
    }

    printf("[FaceVault] rPPG — passed: BPM=%.1f confidence=%.2f\n",
           result.heartRate.bpm,
           result.heartRate.confidence);
    return true;
}

bool FaceVaultLivenessV4::checkMoirePattern(
    const cv::Mat& irFrame) {

    if (irFrame.empty()) return false;

    cv::Mat gray;
    if (irFrame.channels() == 3) {
        cv::cvtColor(irFrame, gray, cv::COLOR_BGR2GRAY);
    } else if (irFrame.channels() == 4) {
        cv::cvtColor(irFrame, gray, cv::COLOR_BGRA2GRAY);
    } else {
        gray = irFrame.clone();
    }

    cv::Mat floatFrame;
    gray.convertTo(floatFrame, CV_32F);

    cv::Mat dft;
    cv::dft(floatFrame, dft, cv::DFT_COMPLEX_OUTPUT);

    cv::Mat planes[2];
    cv::split(dft, planes);
    cv::Mat magnitude;
    cv::magnitude(planes[0], planes[1], magnitude);

    // Log scale
    magnitude += cv::Scalar::all(1);
    cv::log(magnitude, magnitude);

    // DON'T normalise — use raw values
    // Calculate mean and std deviation
    cv::Scalar mean, stddev;
    cv::meanStdDev(magnitude, mean, stddev);

    // Screen has sharp isolated peaks
    // = high std deviation relative to mean
    // Real face has distributed energy
    // = lower std deviation relative to mean

    double ratio = stddev[0] / (mean[0] + 1e-6);

    printf("[FaceVault] Lock 3 FFT — mean=%.3f std=%.3f ratio=%.3f\n",
           mean[0], stddev[0], ratio);

    // Screen = ratio > threshold
    // Real face = ratio < threshold
    // Threshold needs calibration from tests
    return ratio > 1.5;
}

void FaceVaultLivenessV4::reset() {
    _rppg.reset();
//    _evaluated = false; // ← reset flag
    _lastFrame.release();
}

} // namespace FaceVault
