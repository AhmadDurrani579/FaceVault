//
//  rPPGProcessor.cpp
//  PulseCore
//
//  Created by Ahmad on 16/04/2026.
//

#include "rPPGProcessor.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>

namespace FaceVault {

rPPGProcessor::rPPGProcessor()
    : _bufferSize(1800)
    , _warmupFrames(0)
    , _scanStartTime(0.0)
    , _runningRedMean(0.0f)
    , _runningGreenMean(0.0f)
    , _runningBlueMean(0.0f)
    , _alpha(0.95f) {
}

rPPGProcessor::~rPPGProcessor() {}

rPPGFrame rPPGProcessor::processFrame(const cv::Mat& frame,
                                       double timestamp) {
    printf("🫀 rPPG processFrame — warmup=%d timestamp=%.1f empty=%d\n",
           _warmupFrames, timestamp, frame.empty() ? 1 : 0);

    rPPGFrame result;
    result.timestamp    = timestamp;
    result.chromSignal  = 0.0f;
    result.redMean      = 0.0f;
    result.greenMean    = 0.0f;
    result.blueMean     = 0.0f;
    result.faceDetected = false;
    result.isValid      = false;

    if (frame.empty()) return result;

    // Set scan start time on first frame
    _warmupFrames++;
    if (_warmupFrames == 1) {
        _scanStartTime = timestamp;
    }

    // Skip first 15 frames — camera stabilisation
    if (_warmupFrames < 15) return result;

    // Use centre region of frame as forehead proxy
    // In production this would use face detection
    // For now use top-centre 30% of frame
    int roiX = frame.cols * 0.3f;
    int roiY = frame.rows * 0.05f;
    int roiW = frame.cols * 0.4f;
    int roiH = frame.rows * 0.25f;

    // Bounds check
    roiX = std::max(0, roiX);
    roiY = std::max(0, roiY);
    roiW = std::min(roiW, frame.cols - roiX);
    roiH = std::min(roiH, frame.rows - roiY);

    if (roiW <= 0 || roiH <= 0) return result;

    cv::Rect roi(roiX, roiY, roiW, roiH);
    cv::Vec3f means = roiMeans(frame, roi);

    result.redMean   = means[2]; // BGR → R
    result.greenMean = means[1];
    result.blueMean  = means[0];
    result.faceDetected = true;

    // Update running means with exponential smoothing
    if (_buffer.empty()) {
        _runningRedMean   = result.redMean;
        _runningGreenMean = result.greenMean;
        _runningBlueMean  = result.blueMean;
    } else {
        _runningRedMean   = _alpha * _runningRedMean +
                            (1.0f - _alpha) * result.redMean;
        _runningGreenMean = _alpha * _runningGreenMean +
                            (1.0f - _alpha) * result.greenMean;
        _runningBlueMean  = _alpha * _runningBlueMean +
                            (1.0f - _alpha) * result.blueMean;
    }

    // Protect against division by zero
    if (_runningRedMean   < 1e-6f) _runningRedMean   = 1.0f;
    if (_runningGreenMean < 1e-6f) _runningGreenMean = 1.0f;
    if (_runningBlueMean  < 1e-6f) _runningBlueMean  = 1.0f;

    // Normalise channels by running mean
    float rNorm = result.redMean   / _runningRedMean;
    float gNorm = result.greenMean / _runningGreenMean;
    float bNorm = result.blueMean  / _runningBlueMean;

    // Apply CHROM algorithm
    result.chromSignal = applyChrom(rNorm, gNorm, bNorm,
                                     _runningRedMean,
                                     _runningGreenMean,
                                     _runningBlueMean);
    printf("🫀 chrom=%.4f rNorm=%.4f gNorm=%.4f bNorm=%.4f\n",
           result.chromSignal, rNorm, gNorm, bNorm);

    result.isValid = true;

    // Add to buffer
    _buffer.push_back(result);
    if (_buffer.size() > _bufferSize) {
        _buffer.pop_front();
    }

    return result;
}

// ── CHROM algorithm ───────────────────────────────────────────────────────
// de Haan & Jeanne (2013)
// Separates heartbeat signal from motion artifacts
// using the different spectral properties of skin vs motion

float rPPGProcessor::applyChrom(float rNorm,
                                  float gNorm,
                                  float bNorm,
                                  float rMean,
                                  float gMean,
                                  float bMean) {
    // Step 1 — build two orthogonal signal components
    // Xs amplifies the heartbeat (R goes up, G goes down)
    // Ys captures motion reference (all channels move together)
    float Xs = 3.0f * rNorm - 2.0f * gNorm;
    float Ys = 1.5f * rNorm + gNorm - 1.5f * bNorm;

    // Step 2 — compute alpha scaling factor
    // from standard deviation ratio of accumulated signals
    float alpha = 1.0f;

    if (_buffer.size() >= 30) {
        // Compute std dev of Xs and Ys over recent window
        std::vector<float> xsVals, ysVals;
        size_t windowStart = _buffer.size() > 60 ?
                             _buffer.size() - 60 : 0;

        for (size_t i = windowStart; i < _buffer.size(); i++) {
            const auto& f = _buffer[i];
            if (!f.isValid) continue;

            float r = f.redMean   / _runningRedMean;
            float g = f.greenMean / _runningGreenMean;
            float b = f.blueMean  / _runningBlueMean;

            xsVals.push_back(3.0f * r - 2.0f * g);
            ysVals.push_back(1.5f * r + g - 1.5f * b);
        }

        if (!xsVals.empty() && !ysVals.empty()) {
            // Standard deviation of Xs
            float xsMean = std::accumulate(xsVals.begin(),
                           xsVals.end(), 0.0f) / xsVals.size();
            float xsVar = 0.0f;
            for (float v : xsVals) xsVar += (v-xsMean)*(v-xsMean);
            float xsStd = std::sqrt(xsVar / xsVals.size());

            // Standard deviation of Ys
            float ysMean = std::accumulate(ysVals.begin(),
                           ysVals.end(), 0.0f) / ysVals.size();
            float ysVar = 0.0f;
            for (float v : ysVals) ysVar += (v-ysMean)*(v-ysMean);
            float ysStd = std::sqrt(ysVar / ysVals.size());

            // Alpha = ratio of standard deviations
            if (ysStd > 1e-6f) {
                alpha = xsStd / ysStd;
            }
        }
    }

    // Step 3 — subtract scaled motion component
    // What remains is the heartbeat signal
    return Xs - alpha * Ys;
}

// ── ROI means ─────────────────────────────────────────────────────────────

cv::Vec3f rPPGProcessor::roiMeans(const cv::Mat& frame,
                                    const cv::Rect& roi) {
    cv::Mat roiMat = frame(roi);
    cv::Scalar means = cv::mean(roiMat);
    return cv::Vec3f(means[0], means[1], means[2]);
}

// ── Forehead ROI from face rect ───────────────────────────────────────────

cv::Rect rPPGProcessor::foreheadROI(const cv::Mat& frame,
                                     const cv::Rect& faceRect) {
    // Forehead = top 25% of face rect, centre 60%
    int x = faceRect.x + faceRect.width  * 0.2f;
    int y = faceRect.y + faceRect.height * 0.05f;
    int w = faceRect.width  * 0.6f;
    int h = faceRect.height * 0.25f;

    // Clamp to frame bounds
    x = std::max(0, x);
    y = std::max(0, y);
    w = std::min(w, frame.cols - x);
    h = std::min(h, frame.rows - y);

    return cv::Rect(x, y, w, h);
}

// ── Get signal ────────────────────────────────────────────────────────────

rPPGSignal rPPGProcessor::getSignal() const {
    rPPGSignal signal;

    for (const auto& frame : _buffer) {
        if (frame.isValid) {
            signal.chrom.push_back(frame.chromSignal);
            signal.red.push_back(frame.redMean);
            signal.green.push_back(frame.greenMean);
            signal.blue.push_back(frame.blueMean);
            signal.timestamps.push_back(frame.timestamp);
        }
    }

    return signal;
}

// ── Signal quality ────────────────────────────────────────────────────────

float rPPGProcessor::signalQuality() const {
    if (_buffer.size() < 30) return 0.0f;

    // Quality based on variance of chrom signal
    // Higher variance = stronger heartbeat signal detected
    std::vector<float> chromValues;
    for (const auto& f : _buffer) {
        if (f.isValid) chromValues.push_back(f.chromSignal);
    }

    if (chromValues.empty()) return 0.0f;

    float mean = std::accumulate(chromValues.begin(),
                                  chromValues.end(), 0.0f)
                 / chromValues.size();

    float variance = 0.0f;
    for (float v : chromValues) {
        variance += (v - mean) * (v - mean);
    }
    variance /= chromValues.size();

    // Normalise — rPPG signal variance is typically much smaller
    // than finger PPG so use a lower normalisation factor
    float quality = std::min(variance / 0.01f, 1.0f);
    return quality;
}

// ── Scan duration ─────────────────────────────────────────────────────────

double rPPGProcessor::scanDuration() const {
    if (_buffer.empty()) return 0.0;
    if (_scanStartTime <= 0) return 0.0;
    return _buffer.back().timestamp - _scanStartTime;
}

// ── Reset ─────────────────────────────────────────────────────────────────

void rPPGProcessor::reset() {
    _buffer.clear();
    _warmupFrames     = 0;
    _scanStartTime    = 0.0;
    _runningRedMean   = 0.0f;
    _runningGreenMean = 0.0f;
    _runningBlueMean  = 0.0f;
}

void rPPGProcessor::setBufferSize(size_t size) {
    _bufferSize = size;
}

} // namespace FaceVault
