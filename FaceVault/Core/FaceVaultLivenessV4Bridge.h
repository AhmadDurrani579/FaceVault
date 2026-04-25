//
//  FaceVaultGeometricBridge.h
//  FaceVault
//
//  Created by Ahmad on 10/04/2026.
//

#pragma once
#import <Foundation/Foundation.h>
#import <ARKit/ARKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceVaultLivenessV4Bridge : NSObject

- (void)processFrame:(CVPixelBufferRef)pixelBuffer
           timestamp:(double)timestamp
                 fps:(float)fps;

- (BOOL)hasEnoughData;
- (NSDictionary *)evaluate;
- (void)reset;
- (double)scanDuration;

@end

NS_ASSUME_NONNULL_END
