//
//  FaceVaultLivenessV4Bridge.m
//  FaceVault
//
//  Created by Ahmad on 25/04/2026.
//

#include <opencv2/opencv.hpp>

#import "FaceVaultLivenessV4Bridge.h"
#import "FaceVaultLivenessV4.hpp"

@implementation FaceVaultLivenessV4Bridge {
    FaceVault::FaceVaultLivenessV4 _engine;
}

- (void)processFrame:(CVPixelBufferRef)pixelBuffer
           timestamp:(double)timestamp
                 fps:(float)fps {

    if (pixelBuffer == nil) return;

    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    NSLog(@"🫀 pixel format: %d", (int)format);

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    int width  = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);

    cv::Mat rgb;

    if (format == kCVPixelFormatType_32BGRA) {
        void* base = CVPixelBufferGetBaseAddress(pixelBuffer);
        if (!base) {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            return;
        }
        cv::Mat bgra(height, width, CV_8UC4, base);
        cv::cvtColor(bgra, rgb, cv::COLOR_BGRA2BGR);

    } else if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
               format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {

        void* yBase  = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        void* uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        size_t yStride  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        int uvHeight = height / 2;

        if (!yBase || !uvBase) {
            CVPixelBufferUnlockBaseAddress(pixelBuffer,
                kCVPixelBufferLock_ReadOnly);
            return;
        }

        // Use stride-aware Mats directly
        cv::Mat yMat(height, width, CV_8UC1, yBase, yStride);
        cv::Mat uvMat(uvHeight, width, CV_8UC1, uvBase, uvStride);

        // Stack Y and UV into NV12 layout
        cv::Mat nv12;
        cv::vconcat(yMat, uvMat, nv12);

        // Convert to BGR
        int code = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                   ? cv::COLOR_YUV2BGR_NV12
                   : cv::COLOR_YUV2BGR_NV21;

        cv::cvtColor(nv12, rgb, code);
    }
    else {
        NSLog(@"🫀 unknown format: %d", (int)format);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return;
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    if (!rgb.empty()) {
        NSLog(@"🫀 calling C++ processFrame size=%dx%d", rgb.cols, rgb.rows);
        _engine.processFrame(rgb, timestamp, fps);
    }
}

- (double)scanDuration {
    return _engine.scanDuration();
}

- (BOOL)hasEnoughData {
    return _engine.hasEnoughData();
}

- (NSDictionary *)evaluate {
    FaceVault::LivenessV4Result result = _engine.evaluate();

    return @{
        @"isLive":          @(result.isLive),
        @"pulseDetected":   @(result.pulseDetected),
        @"screenDetected":  @(result.screenDetected),
        @"heartRateBPM":    @(result.heartRateBPM),
        @"confidence":      @(result.confidence),
        @"rejectReason":    @(result.rejectReason.c_str())
    };
}

- (void)reset {
    _engine.reset();
}

@end
