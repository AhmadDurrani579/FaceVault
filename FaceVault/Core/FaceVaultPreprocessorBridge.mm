//
//  FaceVaultPreprocessorBridge.m
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#import <Foundation/Foundation.h>
#import "FaceVaultPreprocessorBridge.h"
#include "FaceVaultPreprocessor.hpp"

@implementation FaceVaultFaceRect
@end

@implementation FaceVaultPreprocessResult
@end

@implementation FaceVaultPreprocessorBridge

- (FaceVaultPreprocessResult *)process:(CVPixelBufferRef)pixelBuffer
                              faceRect:(FaceVaultFaceRect *)faceRect {
    // Lock pixel buffer
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Check if planar
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    void *base = nil;
    int rowBytes = 0;
    
    if (planeCount > 0) {
        base     = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        rowBytes = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    } else {
        base     = CVPixelBufferGetBaseAddress(pixelBuffer);
        rowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    }
    
    // Safety check
    if (base == nil) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        FaceVaultPreprocessResult *result = [[FaceVaultPreprocessResult alloc] init];
        result.success = NO;
        result.error = @"Null pixel buffer base address";
        return result;
    }
    
    int width  = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    facevault::ImageBuffer frame;
    frame.width    = width;
    frame.height   = height;
    frame.channels = 4;
    frame.data.resize(width * height * 4);
    
    uint8_t *src = (uint8_t *)base;
    for (int row = 0; row < height; row++) {
        memcpy(frame.data.data() + row * width * 4,
               src + row * rowBytes,
               width * 4);
    }

    // Build FaceRect
    facevault::FaceRect rect;
    rect.x             = faceRect.x;
    rect.y             = faceRect.y;
    rect.width         = faceRect.width;
    rect.height        = faceRect.height;
    rect.yaw           = faceRect.yaw;
    rect.pitch         = faceRect.pitch;
    rect.roll          = faceRect.roll;
    rect.landmarkCount = faceRect.landmarkCount;
    
    rect.leftEyeX  = faceRect.leftEyeX;
    rect.leftEyeY  = faceRect.leftEyeY;
    rect.rightEyeX = faceRect.rightEyeX;
    rect.rightEyeY = faceRect.rightEyeY;

    
    NSLog(@"🔍 Calling preprocessor — width:%d height:%d channels:%d",
          frame.width, frame.height, frame.channels);

    // Run C++ preprocessor
    facevault::FacePreprocessor preprocessor;
    facevault::PreprocessResult cResult = preprocessor.process(frame, rect);
    
    NSLog(@"🔍 Preprocess result — success:%d quality:%.2f",
          cResult.success, cResult.qualityScore);

    // Convert result back to ObjC
    FaceVaultPreprocessResult *result = [[FaceVaultPreprocessResult alloc] init];
    result.success      = cResult.success;
    result.qualityScore = cResult.qualityScore;
    result.distanceScore = cResult.distanceScore;
    result.tooFar        = cResult.tooFar;
    result.tooClose      = cResult.tooClose;

    result.error        = cResult.success ? nil : [NSString stringWithUTF8String:cResult.error.c_str()];
    
    if (cResult.success) {
        result.croppedFace = [NSData dataWithBytes:cResult.croppedFace.data.data()
                                            length:cResult.croppedFace.data.size()];
        
        // Build CVPixelBuffer directly here
        CVPixelBufferRef outBuffer = nil;
        CVPixelBufferCreate(kCFAllocatorDefault, 160, 160,
                            kCVPixelFormatType_32BGRA, nil, &outBuffer);
        
        CVPixelBufferLockBaseAddress(outBuffer, 0);
        uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(outBuffer);
        const uint8_t *src = (const uint8_t *)result.croppedFace.bytes;
        int pixelCount = 160 * 160;
        
        for (int i = 0; i < pixelCount; i++) {
            dst[i * 4 + 0] = src[i * 3 + 2]; // B
            dst[i * 4 + 1] = src[i * 3 + 1]; // G
            dst[i * 4 + 2] = src[i * 3 + 0]; // R
            dst[i * 4 + 3] = 255;             // A
        }
        
        CVPixelBufferUnlockBaseAddress(outBuffer, 0);
        result.processedBuffer = outBuffer;
    }
    
    return result;
}

- (CVPixelBufferRef)processedPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                faceRect:(FaceVaultFaceRect *)faceRect {
    FaceVaultPreprocessResult *result = [self process:pixelBuffer faceRect:faceRect];
    
    if (!result.success || !result.croppedFace) return nil;
    
    // Convert NSData → CVPixelBuffer 160x160
    CVPixelBufferRef outBuffer = nil;
    CVPixelBufferCreate(kCFAllocatorDefault,
                        160, 160,
                        kCVPixelFormatType_32BGRA,
                        nil,
                        &outBuffer);
    
    CVPixelBufferLockBaseAddress(outBuffer, 0);
    void *dst = CVPixelBufferGetBaseAddress(outBuffer);
    
    // result is RGB 3-channel — convert to BGRA 4-channel
    const uint8_t *src = (const uint8_t *)result.croppedFace.bytes;
    uint8_t *dstPtr = (uint8_t *)dst;
    int pixelCount = 160 * 160;
    
    for (int i = 0; i < pixelCount; i++) {
        dstPtr[i * 4 + 0] = src[i * 3 + 2]; // B
        dstPtr[i * 4 + 1] = src[i * 3 + 1]; // G
        dstPtr[i * 4 + 2] = src[i * 3 + 0]; // R
        dstPtr[i * 4 + 3] = 255;             // A
    }
    
    CVPixelBufferUnlockBaseAddress(outBuffer, 0);
    return outBuffer;
}


@end
