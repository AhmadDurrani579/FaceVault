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
@end

@interface FaceVaultPreprocessResult : NSObject
@property (nonatomic, strong) NSData *croppedFace; // 160x160 BGRA
@property (nonatomic) float qualityScore;
@property (nonatomic) BOOL  success;
@property (nonatomic, strong) NSString *error;
@end


@interface FaceVaultPreprocessorBridge : NSObject
- (FaceVaultPreprocessResult *)process:(CVPixelBufferRef)pixelBuffer
                              faceRect:(FaceVaultFaceRect *)faceRect;
@end

#endif /* FaceVaultPreprocessorBridge_h */
