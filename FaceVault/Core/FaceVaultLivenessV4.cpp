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
    _rppg.setBufferSize(300); // 60 frames = ~10 seconds
}

void FaceVaultLivenessV4::processFrame(
    const cv::Mat& irFrame,
    double timestamp,
    float fps) {

    // Feed frame into rPPG processor
    _fps = fps;
    _rppg.processFrame(irFrame, timestamp);
}

bool FaceVaultLivenessV4::hasEnoughData() const {
    // Use internal scan duration instead of signal timestamps
    return _rppg.scanDuration() >= 5.0;
}

LivenessV4Result FaceVaultLivenessV4::evaluate() {
    LivenessV4Result result;
    result.isLive = false;
    result.pulseDetected = false;
    result.screenDetected = false;
    result.confidence = 0.0f;

    // Use scanDuration not hasEnoughData
    double duration = _rppg.scanDuration();
    float quality = _rppg.signalQuality();
    
    printf("🫀 C++ scanDuration=%.1f quality=%.2f\n",
           duration, quality);

    if (duration < 5.0) {
        result.rejectReason = "Insufficient data";
        return result;
    }

    // Get signal
    rPPGSignal signal = _rppg.getSignal();
    
    printf("🫀 C++ signal.chrom size=%zu\n", signal.chrom.size());
    printf("🫀 C++ signal duration=%.1f\n", signal.duration());
    
    if (signal.chrom.size() < 30) {
        result.rejectReason = "Signal too short";
        return result;
    }

    if (signal.chrom.empty()) {
        result.rejectReason = "No signal";
        return result;
    }

    // Process signal
    SignalResult signalResult = _signal.processRPPG(
        signal.chrom,
        _fps
    );

    printf("🫀 C++ BPM=%.1f confidence=%.2f valid=%d\n",
           signalResult.heartRate.bpm,
           signalResult.heartRate.confidence,
           signalResult.heartRate.isValid);

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

    if (!result.heartRate.isValid) return false;
    if (result.heartRate.bpm < 40.0f) return false;
    if (result.heartRate.bpm > 180.0f) return false;
    
    // Lower confidence threshold for rPPG
    // rPPG is noisier than finger PPG
    // 0.05 = 5% is enough for face rPPG
    if (result.heartRate.confidence < 0.05f) return false;

    return true;
}

bool FaceVaultLivenessV4::checkMoirePattern(
    const cv::Mat& irFrame) {

    // Lock 3 — FFT screen detection
    // Convert to float
    cv::Mat floatFrame;
    irFrame.convertTo(floatFrame, CV_32F);

    // Apply DFT
    cv::Mat dft;
    cv::dft(floatFrame, dft,
            cv::DFT_COMPLEX_OUTPUT);

    // Shift zero frequency to center
    int cx = dft.cols / 2;
    int cy = dft.rows / 2;

    cv::Mat q0(dft, cv::Rect(0, 0, cx, cy));
    cv::Mat q1(dft, cv::Rect(cx, 0, cx, cy));
    cv::Mat q2(dft, cv::Rect(0, cy, cx, cy));
    cv::Mat q3(dft, cv::Rect(cx, cy, cx, cy));

    cv::Mat tmp;
    q0.copyTo(tmp); q3.copyTo(q0); tmp.copyTo(q3);
    q1.copyTo(tmp); q2.copyTo(q1); tmp.copyTo(q2);

    // Compute magnitude
    cv::Mat planes[2];
    cv::split(dft, planes);
    cv::Mat magnitude;
    cv::magnitude(planes[0], planes[1], magnitude);

    // Log scale
    magnitude += cv::Scalar::all(1);
    cv::log(magnitude, magnitude);
    cv::normalize(magnitude, magnitude,
                  0, 1, cv::NORM_MINMAX);

    // Check for sharp periodic peaks
    // = screen pixel grid signature
    double maxVal;
    cv::minMaxLoc(magnitude, nullptr, &maxVal);

    // Sharp peak > 0.85 = likely screen
    return maxVal > 0.85;
}

void FaceVaultLivenessV4::reset() {
    _rppg.reset();
}

} // namespace FaceVault
