//
//  SignalProcessor.hpp
//  PulseCore
//
//  Created by Ahmad on 16/04/2026.
//

#pragma once

#include <vector>
#include <cstddef>

namespace FaceVault {

struct HeartRateResult {
    float bpm;              // beats per minute
    float confidence;       // 0.0 - 1.0
    bool isValid;
};

struct HRVResult {
    float rmssd;            // root mean square of successive differences
    float sdnn;             // standard deviation of RR intervals
    std::vector<float> rrIntervals;  // individual RR intervals in ms
    bool isValid;
};

struct BreathingResult {
    float breathsPerMinute;
    float confidence;
    bool isValid;
};

struct SignalResult {
    HeartRateResult heartRate;
    HRVResult hrv;
    BreathingResult breathing;
};

class SignalProcessor {
public:
    SignalProcessor();
    ~SignalProcessor();

    // Full processing — takes raw red channel signal
    SignalResult process(const std::vector<float>& signal,
                         float sampleRate);
    
    SignalResult processRPPG(const std::vector<float>& signal,
                              float sampleRate);


private:
    // Butterworth bandpass filter
    std::vector<float> bandpassFilter(const std::vector<float>& signal,
                                       float lowCut,
                                       float highCut,
                                       float sampleRate);

    // FFT-based heart rate
    HeartRateResult extractHeartRate(const std::vector<float>& filtered,
                                      float sampleRate);

    // Peak detection for HRV
    HRVResult extractHRV(const std::vector<float>& filtered,
                          float sampleRate);

    HRVResult extractHRVRelaxed(const std::vector<float>& signal,
                                  float sampleRate);

    // Low frequency FFT for breathing
    BreathingResult extractBreathing(const std::vector<float>& signal,
                                      float sampleRate);

    // Helpers
    std::vector<float> computeFFT(const std::vector<float>& signal);
    std::vector<size_t> findPeaks(const std::vector<float>& signal,
                                   float minDistance,
                                   float minHeight);
    std::vector<float> detrend(const std::vector<float>& signal);
    
    std::vector<float> movingAverage(const std::vector<float>& signal,
                                      int windowSize);
};

} // namespace FaceVault
