//
//  rPPGProcessor.hpp
//  PulseCore
//
//  Created by Ahmad on 16/04/2026.
//

#pragma once

#include <opencv2/opencv.hpp>
#include <vector>
#include <deque>

namespace FaceVault {

struct rPPGFrame {
    double timestamp;
    float chromSignal;
    float redMean;
    float greenMean;
    float blueMean;
    bool faceDetected;
    bool isValid;
};

struct rPPGSignal {
    std::vector<float> chrom;
    std::vector<float> red;
    std::vector<float> green;
    std::vector<float> blue;
    std::vector<double> timestamps;

    bool hasEnoughData() const {
        if (timestamps.size() < 2) return false;
        double duration = timestamps.back() -
                          timestamps.front();
        return duration >= 10.0;
    }

    double duration() const {
        if (timestamps.size() < 2) return 0.0;
        return timestamps.back() - timestamps.front();
    }
};

class rPPGProcessor {
public:
    rPPGProcessor();
    ~rPPGProcessor();

    // Feed one front camera frame in
    rPPGFrame processFrame(const cv::Mat& frame,
                            double timestamp = 0.0);

    // Get accumulated signal
    rPPGSignal getSignal() const;

    // Signal quality 0.0 - 1.0
    float signalQuality() const;

    // Scan duration in seconds
    double scanDuration() const;

    // Reset buffer
    void reset();

    void setBufferSize(size_t size);

private:
    std::deque<rPPGFrame> _buffer;
    size_t _bufferSize;
    int _warmupFrames;
    double _scanStartTime;

    // CHROM algorithm
    // Cancels motion artifacts using all 3 channels
    float applyChrom(float rNorm,
                     float gNorm,
                     float bNorm,
                     float rMean,
                     float gMean,
                     float bMean);

    // Extract forehead ROI — best PPG signal on face
    cv::Rect foreheadROI(const cv::Mat& frame,
                          const cv::Rect& faceRect);

    // Get channel means from ROI
    cv::Vec3f roiMeans(const cv::Mat& frame,
                        const cv::Rect& roi);

    // Running means for CHROM normalisation
    float _runningRedMean;
    float _runningGreenMean;
    float _runningBlueMean;
    float _alpha; // smoothing factor
};

} // namespace FaceVault
