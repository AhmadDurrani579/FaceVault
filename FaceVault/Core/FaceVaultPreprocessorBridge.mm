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
    
    int width    = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height   = (int)CVPixelBufferGetHeight(pixelBuffer);
    int rowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    void *base   = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    // Copy pixel data into C++ ImageBuffer
    facevault::ImageBuffer frame;
    frame.width    = width;
    frame.height   = height;
    frame.channels = 4; // BGRA
    frame.data.resize(width * height * 4);
    
    uint8_t *src = (uint8_t *)base;
    for (int row = 0; row < height; row++) {
        memcpy(frame.data.data() + row * width * 4,
               src + row * rowBytes,
               width * 4);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
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
    
    // Run C++ preprocessor
    facevault::FacePreprocessor preprocessor;
    facevault::PreprocessResult cResult = preprocessor.process(frame, rect);
    
    // Convert result back to ObjC
    FaceVaultPreprocessResult *result = [[FaceVaultPreprocessResult alloc] init];
    result.success      = cResult.success;
    result.qualityScore = cResult.qualityScore;
    result.error        = cResult.success ? nil : [NSString stringWithUTF8String:cResult.error.c_str()];
    
    if (cResult.success) {
        result.croppedFace = [NSData dataWithBytes:cResult.croppedFace.data.data()
                                            length:cResult.croppedFace.data.size()];
    }
    
    return result;
}

@end
