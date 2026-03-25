//
//  FaceVaultSegmentor.hpp
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

#ifndef FaceVaultSegmentor_hpp
#define FaceVaultSegmentor_hpp

#ifdef __cplusplus
#include <vector>
#include <string>
#include <cstdint>
#include "FaceVaultPreprocessor.hpp"

namespace facevault {

struct SegmentResult {
    ImageBuffer segmentedFace;
    ImageBuffer mask;
    float       coverageScore;
    bool        success;
    std::string error;
};

class FaceSegmentor {
public:
    SegmentResult segment(const ImageBuffer& croppedFace) const;

private:
    ImageBuffer bgraToRgb(const ImageBuffer& input) const;
    ImageBuffer grabCutSegment(const ImageBuffer& input) const;
    ImageBuffer applyMask(const ImageBuffer& input,
                          const ImageBuffer& mask) const;
    ImageBuffer fillBackground(const ImageBuffer& masked,
                               const ImageBuffer& mask) const;
};

} // namespace facevault

#endif // __cplusplus

#endif // FaceVaultSegmentor_hpp
