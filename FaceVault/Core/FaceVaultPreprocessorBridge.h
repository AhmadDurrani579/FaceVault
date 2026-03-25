//
//  FaceVaultPreprocessorBridge.h
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#ifndef FaceVaultPreprocessorBridge_h
#define FaceVaultPreprocessorBridge_h

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@interface FaceVaultFaceRect: NSObject
@property (nonatomic) float x;
@property (nonatomic) float y;
@property (nonatomic) float width;
@property (nonatomic) float height;
@property (nonatomic) float yaw;
@property (nonatomic) float pitch;
@property (nonatomic) float roll;
@property (nonatomic) int   landmarkCount;
@property (nonatomic) float leftEyeX;
@property (nonatomic) float leftEyeY;
@property (nonatomic) float rightEyeX;
@property (nonatomic) float rightEyeY;

@end

@interface FaceVaultPreprocessResult : NSObject
@property (nonatomic, strong) NSData *croppedFace; // 160x160 BGRA
@property (nonatomic) float qualityScore;
@property (nonatomic) float distanceScore;
@property (nonatomic) BOOL  tooFar;
@property (nonatomic) BOOL  tooClose;

@property (nonatomic) BOOL  success;
@property (nonatomic, strong) NSString *error;
@property (nonatomic) CVPixelBufferRef processedBuffer;
@end


@interface FaceVaultPreprocessorBridge : NSObject
- (FaceVaultPreprocessResult *)process:(CVPixelBufferRef)pixelBuffer
                              faceRect:(FaceVaultFaceRect *)faceRect;

- (CVPixelBufferRef)processedPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                faceRect:(FaceVaultFaceRect *)faceRect;

@end

#endif /* FaceVaultPreprocessorBridge_h */
