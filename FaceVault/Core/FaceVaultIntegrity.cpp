//
//  FaceVaultIntegrity.cpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#include "FaceVaultIntegrity.hpp"
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>
#include <sys/types.h>

namespace facevault{
IntegrityResult IntegrityChecker::check() const {
    IntegrityResult result;
    result.isJailbroken = false;
    result.isDebuggerAttached = false;
    result.isMemoryTampered = false;
    result.passed = false;
    
    // Check 1 - Jailbreak
    
    if (checkJailbreak()) {
        result.isJailbroken = true;
        result.passed       = false;
        result.reason       = "Jailbreak detected";
        return result;
    }
    
    // Check 2 — Debugger
    if (checkDebugger()) {
        result.isDebuggerAttached = true;
        result.passed             = false;
        result.reason             = "Debugger attached";
        return result;
    }

    // Check 3 — Suspicious libraries
    if (checkSuspiciousLibraries()) {
        result.isMemoryTampered = true;
        result.passed           = false;
        result.reason           = "Suspicious library detected";
        return result;
    }

    // Check 4 — Dyld hooks
    if (checkDyldHooks()) {
        result.isMemoryTampered = true;
        result.passed           = false;
        result.reason           = "Dyld hooks detected";
        return result;
    }

    return result;

}

// MARK: - Jailbreak Check
bool IntegrityChecker::checkJailbreak() const {
    // Check for common jailbreak files
    const char* jailbreakPaths[] = {
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt",
        "/usr/bin/ssh",
        "/private/var/stash",
        "/var/checkra1n.dmg",
        "/usr/lib/libhooker.dylib",
        "/usr/lib/TweakInject.dylib",
        nullptr
    };

    struct stat statInfo;
    for (int i = 0; jailbreakPaths[i] != nullptr; i++) {
        if (stat(jailbreakPaths[i], &statInfo) == 0) {
            return true;
        }
    }

    // Check if app can write outside sandbox
    const char* testPath = "/private/jailbreak_test.txt";
    FILE* f = fopen(testPath, "w");
    if (f != nullptr) {
        fclose(f);
        remove(testPath);
        return true;
    }

    return false;
}

// MARK: - Debugger Check
bool IntegrityChecker::checkDebugger() const {
    // sysctl check
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, size);

    if (sysctl(mib, 4, &info, &size, nullptr, 0) == 0) {
        if (info.kp_proc.p_flag & P_TRACED) {
            return true;
        }
    }

    return false;
}

// MARK: - Suspicious Libraries
bool IntegrityChecker::checkSuspiciousLibraries() const {
    const char* suspiciousLibs[] = {
        "FridaGadget",
        "frida",
        "cynject",
        "libcycript",
        "SSLKillSwitch",
        "substitute",
        "Substrate",
        "TweakInject",
        nullptr
    };

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name == nullptr) continue;

        for (int j = 0; suspiciousLibs[j] != nullptr; j++) {
            if (strstr(name, suspiciousLibs[j]) != nullptr) {
                return true;
            }
        }
    }

    return false;
}

// MARK: - Dyld Hooks
bool IntegrityChecker::checkDyldHooks() const {
    // Check if common system functions are hooked
    void* handle = dlopen("/usr/lib/libc.dylib", RTLD_LAZY);
    if (handle == nullptr) {
        // libc not accessible = possible hook
        return false; // not conclusive
    }

    void* realStat = dlsym(handle, "stat");
    void* ourStat  = (void*)stat;

    dlclose(handle);

    // If addresses differ significantly = hooked
    ptrdiff_t diff = (char*)realStat - (char*)ourStat;
    if (diff < 0) diff = -diff;

    return diff > 0x100000; // 1MB threshold
}
}
