//
//  SignalProcessor.cpp
//  PulseCore
//
//  Created by Ahmad on 16/04/2026.
//

#include "SignalProcessor.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>
#include <complex>


namespace FaceVault {

static const float kPI = 3.14159265358979f;
SignalProcessor::SignalProcessor() {}
SignalProcessor::~SignalProcessor() {}

SignalResult SignalProcessor::process(
    const std::vector<float>& signal,
    float sampleRate) {

    SignalResult result;

    if (signal.size() < 64) {
        result.heartRate.isValid  = false;
        result.hrv.isValid        = false;
        result.breathing.isValid  = false;
        return result;
    }

    // Step 1 — detrend
    std::vector<float> detrended = detrend(signal);

    // Step 2 — bandpass for heartbeat (0.7-2.5 Hz)
    std::vector<float> filtered = bandpassFilter(
        detrended, 0.7f, 2.5f, sampleRate);

    // Step 3 — bandpass for breathing (0.15-0.6 Hz)
    std::vector<float> breathFiltered = bandpassFilter(
        detrended, 0.15f, 0.6f, sampleRate);

    // Step 4 — moving average for peak detection
    // Window = 1/3 second — smooth enough for peaks
    int windowSize = std::max(3,
                     static_cast<int>(sampleRate / 4));
    std::vector<float> smoothed = movingAverage(filtered,
                                                 windowSize);

    // Step 5 — HRV from smoothed signal
    result.hrv = extractHRV(smoothed, sampleRate);

    // Step 6 — heart rate from RR if valid
    if (result.hrv.isValid &&
        result.hrv.rrIntervals.size() >= 4) {

        float meanRR = std::accumulate(
            result.hrv.rrIntervals.begin(),
            result.hrv.rrIntervals.end(), 0.0f) /
            result.hrv.rrIntervals.size();

        result.heartRate.bpm        = 60000.0f / meanRR;
        result.heartRate.isValid    = true;
        result.heartRate.confidence = 0.9f;


    } else {
        // FFT fallback
        result.heartRate = extractHeartRate(filtered,
                                             sampleRate);
    }

    // Step 7 — breathing from bandpass
    result.breathing = extractBreathing(breathFiltered,
                                         sampleRate);

    return result;
}

SignalResult SignalProcessor::processRPPG(
    const std::vector<float>& signal,
    float sampleRate) {

    SignalResult result;

    if (signal.size() < 30) {
        result.heartRate.isValid  = false;
        result.hrv.isValid        = false;
        result.breathing.isValid  = false;
        return result;
    }

    // Step 1 — detrend
    std::vector<float> detrended = detrend(signal);

    // Step 2 — wider bandpass for rPPG (noisier signal)
    std::vector<float> filtered = bandpassFilter(
        detrended, 0.7f, 3.0f, sampleRate);

    // Step 3 — stronger smoothing for rPPG
    // Use larger window than finger PPG
    int windowSize = std::max(5,
                     static_cast<int>(sampleRate / 2));
    std::vector<float> smoothed = movingAverage(filtered,
                                                 windowSize);

    // Step 4 — extract HRV with relaxed thresholds for rPPG
    result.hrv = extractHRVRelaxed(smoothed, sampleRate);

    // Step 5 — heart rate from RR if valid
    if (result.hrv.isValid &&
        result.hrv.rrIntervals.size() >= 3) {
        float meanRR = std::accumulate(
            result.hrv.rrIntervals.begin(),
            result.hrv.rrIntervals.end(), 0.0f) /
            result.hrv.rrIntervals.size();
        result.heartRate.bpm        = 60000.0f / meanRR;
        result.heartRate.isValid    = true;
        result.heartRate.confidence = 0.7f;
    } else {
        result.heartRate = extractHeartRate(filtered, sampleRate);
    }

    // Step 6 — breathing
    std::vector<float> breathFiltered = bandpassFilter(
        detrended, 0.15f, 0.6f, sampleRate);
    result.breathing = extractBreathing(breathFiltered, sampleRate);

    return result;
}

HRVResult SignalProcessor::extractHRVRelaxed(
    const std::vector<float>& filtered,
    float sampleRate) {

    HRVResult result;
    result.isValid = false;

    if (filtered.size() < 64) return result;

    float maxVal = *std::max_element(filtered.begin(),
                                      filtered.end());
    float minVal = *std::min_element(filtered.begin(),
                                      filtered.end());
    float range  = maxVal - minVal;
    if (range < 1e-6f) return result;

    std::vector<float> normalised(filtered.size());
    for (size_t i = 0; i < filtered.size(); i++) {
        normalised[i] = (filtered[i] - minVal) / range;
    }

    // Lower min height for rPPG — weaker signal
    float minDistance = sampleRate * 0.5f;
    float minHeight   = 0.25f; // lower than finger (0.4)

    std::vector<size_t> peaks = findPeaks(normalised,
                                           minDistance,
                                           minHeight);

    if (peaks.size() < 3) return result;

    // First pass
    std::vector<float> allRR;
    for (size_t i = 1; i < peaks.size(); i++) {
        float rrMs = (peaks[i] - peaks[i-1]) /
                      sampleRate * 1000.0f;
        if (rrMs >= 400.0f && rrMs <= 1500.0f) {
            allRR.push_back(rrMs);
        }
    }

    if (allRR.size() < 3) return result;

    // Relaxed median filter — 35% instead of 15%
    std::vector<float> sorted = allRR;
    std::sort(sorted.begin(), sorted.end());
    float median = sorted[sorted.size() / 2];

    for (float rr : allRR) {
        float deviation = std::abs(rr - median) / median;
        if (deviation <= 0.35f) { // relaxed from 0.15
            result.rrIntervals.push_back(rr);
        }
    }

    if (result.rrIntervals.size() < 2) return result;

    // RMSSD
    float sumSqDiff = 0.0f;
    for (size_t i = 1; i < result.rrIntervals.size(); i++) {
        float diff = result.rrIntervals[i] -
                     result.rrIntervals[i-1];
        sumSqDiff += diff * diff;
    }
    result.rmssd = std::sqrt(sumSqDiff /
                   (result.rrIntervals.size() - 1));

    if (result.rmssd > 200.0f || std::isnan(result.rmssd)) {
        return result;
    }

    float meanRR = std::accumulate(result.rrIntervals.begin(),
                                    result.rrIntervals.end(),
                                    0.0f) /
                   result.rrIntervals.size();

    float sumSq = 0.0f;
    for (float rr : result.rrIntervals) {
        sumSq += (rr - meanRR) * (rr - meanRR);
    }
    result.sdnn    = std::sqrt(sumSq / result.rrIntervals.size());
    result.isValid = true;

    return result;
}



std::vector<float> SignalProcessor::movingAverage(
    const std::vector<float>& signal, int windowSize) {

    if (windowSize < 1) windowSize = 1;
    std::vector<float> result(signal.size(), 0.0f);

    for (size_t i = 0; i < signal.size(); i++) {
        int start = std::max(0, (int)i - windowSize/2);
        int end   = std::min((int)signal.size()-1,
                              (int)i + windowSize/2);
        float sum = 0.0f;
        for (int j = start; j <= end; j++) {
            sum += signal[j];
        }
        result[i] = sum / (end - start + 1);
    }
    return result;
}

// ── Butterworth bandpass filter (2nd order) ──────────────────────────────

std::vector<float> SignalProcessor::bandpassFilter(
    const std::vector<float>& signal,
    float lowCut, float highCut, float sampleRate) {

    std::vector<float> output(signal.size(), 0.0f);

    // Normalise frequencies
    float nyquist = sampleRate / 2.0f;
    float low  = lowCut  / nyquist;
    float high = highCut / nyquist;

    // 2nd order Butterworth coefficients
    float w0l = 2.0f * kPI * low;
    float w0h = 2.0f * kPI * high;

    float cosL = std::cos(w0l);
    float cosH = std::cos(w0h);
    float sinL = std::sin(w0l);
    float sinH = std::sin(w0h);

    float alphaL = sinL / (2.0f * 0.707f);
    float alphaH = sinH / (2.0f * 0.707f);

    // Highpass coefficients
    float b0h =  (1.0f + cosH) / 2.0f;
    float b1h = -(1.0f + cosH);
    float b2h =  (1.0f + cosH) / 2.0f;
    float a0h =   1.0f + alphaH;
    float a1h =  -2.0f * cosH;
    float a2h =   1.0f - alphaH;

    // Lowpass coefficients
    float b0l =  (1.0f - cosL) / 2.0f;
    float b1l =   1.0f - cosL;
    float b2l =  (1.0f - cosL) / 2.0f;
    float a0l =   1.0f + alphaL;
    float a1l =  -2.0f * cosL;
    float a2l =   1.0f - alphaL;

    // Normalise
    b0h /= a0h; b1h /= a0h; b2h /= a0h;
    a1h /= a0h; a2h /= a0h;
    b0l /= a0l; b1l /= a0l; b2l /= a0l;
    a1l /= a0l; a2l /= a0l;

    // Apply highpass first
    std::vector<float> highpassed(signal.size(), 0.0f);
    float x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (size_t i = 0; i < signal.size(); i++) {
        float x0 = signal[i];
        float y0 = b0h*x0 + b1h*x1 + b2h*x2 - a1h*y1 - a2h*y2;
        highpassed[i] = y0;
        x2 = x1; x1 = x0;
        y2 = y1; y1 = y0;
    }

    // Apply lowpass to highpassed signal
    x1 = 0; x2 = 0; y1 = 0; y2 = 0;
    for (size_t i = 0; i < signal.size(); i++) {
        float x0 = highpassed[i];
        float y0 = b0l*x0 + b1l*x1 + b2l*x2 - a1l*y1 - a2l*y2;
        output[i] = y0;
        x2 = x1; x1 = x0;
        y2 = y1; y1 = y0;
    }

    return output;
}

// ── FFT (Cooley-Tukey algorithm) ────────────────────────────────────────────────────

std::vector<float> SignalProcessor::computeFFT(
    const std::vector<float>& signal) {

    // Next power of 2
    size_t n = 1;
    while (n < signal.size()) n <<= 1;

    std::vector<std::complex<float>> x(n, 0.0f);
    for (size_t i = 0; i < signal.size(); i++) {
        x[i] = signal[i];
    }

    // Cooley-Tukey FFT
    for (size_t len = 2; len <= n; len <<= 1) {
        float angle = -2.0f * kPI / len;
        std::complex<float> wlen(std::cos(angle), std::sin(angle));
        for (size_t i = 0; i < n; i += len) {
            std::complex<float> w(1.0f, 0.0f);
            for (size_t j = 0; j < len / 2; j++) {
                std::complex<float> u = x[i + j];
                std::complex<float> v = x[i + j + len/2] * w;
                x[i + j]         = u + v;
                x[i + j + len/2] = u - v;
                w *= wlen;
            }
        }
    }

    // Return magnitudes
    std::vector<float> magnitudes(n / 2);
    for (size_t i = 0; i < n / 2; i++) {
        magnitudes[i] = std::abs(x[i]);
    }
    return magnitudes;
}

// ── Heart rate from FFT ───────────────────────────────────────────────────

HeartRateResult SignalProcessor::extractHeartRate(
    const std::vector<float>& filtered, float sampleRate) {

    HeartRateResult result;
    result.isValid = false;

    if (filtered.size() < 64) return result;

    // Normalise
    float maxVal = *std::max_element(filtered.begin(),
                                      filtered.end());
    float minVal = *std::min_element(filtered.begin(),
                                      filtered.end());
    float range  = maxVal - minVal;
    if (range < 1e-6f) return result;

    std::vector<float> normalised(filtered.size());
    for (size_t i = 0; i < filtered.size(); i++) {
        normalised[i] = (filtered[i] - minVal) / range;
    }

    std::vector<float> magnitudes = computeFFT(normalised);

    size_t n      = filtered.size();
    float freqRes = sampleRate / static_cast<float>(n);

    // Search 0.7 - 2.5 Hz (42 - 150 BPM)
    size_t lowBin  = static_cast<size_t>(0.7f / freqRes);
    size_t highBin = static_cast<size_t>(2.5f / freqRes);
    highBin = std::min(highBin, magnitudes.size() - 1);

    // Find top 3 peaks in FFT
    struct Peak { size_t bin; float mag; };
    std::vector<Peak> peaks;

    for (size_t i = lowBin + 1; i < highBin; i++) {
        if (magnitudes[i] > magnitudes[i-1] &&
            magnitudes[i] > magnitudes[i+1]) {
            peaks.push_back({i, magnitudes[i]});
        }
    }

    // Sort by magnitude
    std::sort(peaks.begin(), peaks.end(),
              [](const Peak& a, const Peak& b) {
                  return a.mag > b.mag;
              });

    if (peaks.empty()) return result;

    // Pick lowest frequency strong peak
    // (fundamental, not harmonic)
    size_t bestBin = peaks[0].bin;

    // Check if a lower frequency peak is within
    // 70% of strongest — that's the fundamental
    for (const auto& p : peaks) {
        if (p.bin < bestBin &&
            p.mag >= peaks[0].mag * 0.7f) {
            bestBin = p.bin;
        }
    }

    float peakFreq   = bestBin * freqRes;
    result.bpm       = peakFreq * 60.0f;
    result.isValid   = true;
    float maxMag = *std::max_element(
        magnitudes.begin(), magnitudes.end());
    if (maxMag > 1e-6f) {
        result.confidence = std::min(
            peaks[0].mag / maxMag, 1.0f
        );
    } else {
        result.confidence = 0.0f;
    }
    return result;
}

// ── HRV from peak detection ───────────────────────────────────────────────

HRVResult SignalProcessor::extractHRV(
    const std::vector<float>& filtered,
    float sampleRate) {

    HRVResult result;
    result.isValid = false;

    if (filtered.size() < 64) return result;

    // Normalise signal to 0-1 range
    float maxVal = *std::max_element(filtered.begin(),
                                      filtered.end());
    float minVal = *std::min_element(filtered.begin(),
                                      filtered.end());
    float range  = maxVal - minVal;

    if (range < 1e-6f) return result;

    std::vector<float> normalised(filtered.size());
    for (size_t i = 0; i < filtered.size(); i++) {
        normalised[i] = (filtered[i] - minVal) / range;
    }

    // Find peaks on normalised signal
    float minDistance = sampleRate * 0.5f;
    float minHeight   = 0.4f;

    std::vector<size_t> peaks = findPeaks(normalised,
                                           minDistance,
                                           minHeight);


    if (peaks.size() < 3) return result;

    // First pass — collect all valid intervals
    std::vector<float> allRR;
    for (size_t i = 1; i < peaks.size(); i++) {
        float rrMs = (peaks[i] - peaks[i-1]) /
                      sampleRate * 1000.0f;
        if (rrMs >= 400.0f && rrMs <= 1500.0f) {
            allRR.push_back(rrMs);
        }
    }

    if (allRR.size() < 4) return result;

    // Second pass — remove outliers using median
    std::vector<float> sorted = allRR;
    std::sort(sorted.begin(), sorted.end());
    float median = sorted[sorted.size() / 2];

    // Keep only intervals within 30% of median
    for (float rr : allRR) {
        float deviation = std::abs(rr - median) / median;
        if (deviation <= 0.15f) {
            result.rrIntervals.push_back(rr);
//            printf("✅ RR kept: %.1f ms\n", rr);
        } else {
            printf("❌ RR rejected: %.1f ms\n", rr);
        }
    }

    if (result.rrIntervals.size() < 2) return result;

    // RMSSD
    float sumSqDiff = 0.0f;
    for (size_t i = 1; i < result.rrIntervals.size(); i++) {
        float diff = result.rrIntervals[i] -
                     result.rrIntervals[i-1];
        sumSqDiff += diff * diff;
    }
    result.rmssd = std::sqrt(sumSqDiff /
                   (result.rrIntervals.size() - 1));

    // Sanity check
    if (result.rmssd > 200.0f || std::isnan(result.rmssd)) {
        result.rmssd   = 0.0f;
        result.isValid = false;
        return result;
    }

    // SDNN
    float meanRR = std::accumulate(
        result.rrIntervals.begin(),
        result.rrIntervals.end(), 0.0f) /
        result.rrIntervals.size();

    float sumSq = 0.0f;
    for (float rr : result.rrIntervals) {
        sumSq += (rr - meanRR) * (rr - meanRR);
    }
    result.sdnn    = std::sqrt(sumSq /
                    result.rrIntervals.size());
    result.isValid = true;

    return result;
}

// ── Breathing rate ────────────────────────────────────────────────────────

BreathingResult SignalProcessor::extractBreathing(
    const std::vector<float>& signal,
    float sampleRate) {

    BreathingResult result;
    result.isValid = false;

    if (signal.size() < 64) return result;

    // Normalise before FFT
    float maxVal = *std::max_element(signal.begin(),
                                      signal.end());
    float minVal = *std::min_element(signal.begin(),
                                      signal.end());
    float range  = maxVal - minVal;

    if (range < 1e-6f) return result;

    std::vector<float> normalised(signal.size());
    for (size_t i = 0; i < signal.size(); i++) {
        normalised[i] = (signal[i] - minVal) / range;
    }

    std::vector<float> magnitudes = computeFFT(normalised);
    float freqRes = sampleRate /
                    static_cast<float>(signal.size());

    // Search 0.1-0.5 Hz (6-30 breaths/min)
    size_t lowBin  = static_cast<size_t>(0.15f / freqRes);
    size_t highBin = static_cast<size_t>(0.6f / freqRes);
    highBin = std::min(highBin, magnitudes.size() - 1);

    if (lowBin >= highBin) return result;

    size_t peakBin = lowBin;
    float  peakMag = 0.0f;
    for (size_t i = lowBin; i <= highBin; i++) {
        if (magnitudes[i] > peakMag) {
            peakMag = magnitudes[i];
            peakBin = i;
        }
    }

    float peakFreq          = peakBin * freqRes;
    result.breathsPerMinute = peakFreq * 60.0f;
    result.confidence       = std::min(peakMag, 1.0f);
    result.isValid          = true;
    
    if (result.breathsPerMinute < 6.0f ||
        result.breathsPerMinute > 30.0f) {
        result.breathsPerMinute = 14.0f; // default to normal
        result.confidence = 0.3f;
    }

    return result;
}


// ── Peak detection ────────────────────────────────────────────────────────
std::vector<size_t> SignalProcessor::findPeaks(
    const std::vector<float>& signal,
    float minDistance, float minHeight) {

    std::vector<size_t> peaks;
    size_t minDist = static_cast<size_t>(minDistance);

    for (size_t i = 1; i + 1 < signal.size(); i++) {
        if (signal[i] > signal[i-1] &&
            signal[i] > signal[i+1] &&
            signal[i] >= minHeight) {

            // Enforce minimum distance from last peak
            if (peaks.empty() || (i - peaks.back()) >= minDist) {
                peaks.push_back(i);
            } else if (signal[i] > signal[peaks.back()]) {
                // Replace last peak if current is stronger
                peaks.back() = i;
            }
        }
    }

    return peaks;
}

// ── Detrend ───────────────────────────────────────────────────────────────

std::vector<float> SignalProcessor::detrend(
    const std::vector<float>& signal) {

    if (signal.empty()) return signal;

    // Simple linear detrend
    size_t n = signal.size();
    float sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (size_t i = 0; i < n; i++) {
        float x = static_cast<float>(i);
        sumX  += x;
        sumY  += signal[i];
        sumXY += x * signal[i];
        sumX2 += x * x;
    }

    float slope     = (n * sumXY - sumX * sumY) /
                      (n * sumX2 - sumX * sumX);
    float intercept = (sumY - slope * sumX) / n;

    std::vector<float> detrended(n);
    for (size_t i = 0; i < n; i++) {
        detrended[i] = signal[i] - (slope * i + intercept);
    }

    return detrended;
}

} // namespace FaceVault
