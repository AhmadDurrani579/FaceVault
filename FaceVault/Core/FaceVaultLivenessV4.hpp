//
//  FaceVaultLivenessV4.hpp
//  FaceVault
//
//  Created by Ahmad on 25/04/2026.
//

#pragma once

#include "rPPGProcessor.hpp"
#include "SignalProcessor.hpp"
#include <vector>

namespace FaceVault {

struct LivenessV4Result {
    bool isLive;
    bool pulseDetected;      // Lock 1
    bool screenDetected;     // Lock 3
    float heartRateBPM;
    float confidence;
    std::string rejectReason;
};

class FaceVaultLivenessV4 {
public:
    FaceVaultLivenessV4();

    // Feed ARKit IR frame
    void processFrame(const cv::Mat& irFrame,
                      double timestamp,
                      float fps = 60.0f);

    // Get liveness decision
    LivenessV4Result evaluate();

    // Reset
    void reset();

    bool hasEnoughData() const;
    double scanDuration() const;

private:
    rPPGProcessor _rppg;
    SignalProcessor _signal;
    float _fps = 60.0f;

    // Lock 1 — pulse check
    bool checkBiologicalPulse(const SignalResult& result);

    // Lock 3 — screen FFT check
    bool checkMoirePattern(const cv::Mat& irFrame);
};

} // namespace FaceVault
