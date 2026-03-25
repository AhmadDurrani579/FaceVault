//
//  FaceVaultPreprocessor.hpp
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#ifndef FaceVaultPreprocessor_hpp
#define FaceVaultPreprocessor_hpp

#ifdef __cplusplus
#include <vector>
#include <string>
#include <cstdint>

namespace facevault {

struct ImageBuffer {
    std::vector<uint8_t> data;
    int width;
    int height;
    int channels;
};

struct FaceRect {
    float x;
    float y;
    float width;
    float height;
    float yaw;
    float pitch;
    float roll;
    int   landmarkCount;
};

struct PreprocessResult {
    ImageBuffer croppedFace;
    float       qualityScore;
    bool        success;
    std::string error;
};

class FacePreprocessor {
public:
    PreprocessResult process(const ImageBuffer& frame,
                             const FaceRect& faceRect) const;

    ImageBuffer cropFace(const ImageBuffer& frame,
                         const FaceRect& faceRect) const;

    ImageBuffer resize(const ImageBuffer& input,
                       int targetWidth,
                       int targetHeight) const;

    ImageBuffer normalize(const ImageBuffer& input) const;

    float qualityScore(const ImageBuffer& face,
                       const FaceRect& faceRect) const;

private:
    int   targetSize = 160;
    float minQuality = 0.5f;
    float maxYaw     = 0.4f;
    float maxPitch   = 0.4f;
    float maxRoll    = 0.4f;
};

} // namespace facevault
#endif // __cplusplus

#endif /* FaceVaultPreprocessor_hpp */
