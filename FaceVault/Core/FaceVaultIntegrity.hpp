//
//  FaceVaultIntegrity.hpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#ifndef FaceVaultIntegrity_hpp
#define FaceVaultIntegrity_hpp

#ifdef __cplusplus
#include <string>
namespace facevault {

struct IntegrityResult {
    bool isJailbroken;
    bool isDebuggerAttached;
    bool isMemoryTampered;
    bool passed;           // true = all checks passed
    std::string reason;    // why it failed
};

class IntegrityChecker {
public:
    // Run all checks
    IntegrityResult check() const;

private:
    // Individual checks
    bool checkJailbreak()  const;
    bool checkDebugger()   const;
    bool checkDyldHooks()  const;
    bool checkSuspiciousLibraries() const;
};

} // namespace facevault

#endif // __cplusplus
#endif // FaceVaultIntegrity_hpp
