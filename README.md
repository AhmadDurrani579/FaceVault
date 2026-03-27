# FaceVault SDK

> **100% On-Device Face Authentication for iOS**  
> Built with ARKit TrueDepth · ArcFace R100 · C++ Core · Secure Enclave

---

## Why FaceVault?

Most face authentication SDKs send your face data to a server. FaceVault never does.  
Every embedding, every comparison, every decision happens entirely on the device.

---

## Accuracy

| Benchmark | Score |
|---|---|
| LFW (Labeled Faces in the Wild) | **99.77%** |
| Real-world authentication | **98-99%** |
| Embedding dimensions | **512-dim ArcFace R100** |
| Liveness detection | **ARKit TrueDepth (hardware level)** |
| False accept rate (estimated) | **< 0.01%** |

---

## Features

### Face Enrollment
- Face ID style progress ring UI
- 5-zone head movement tracking (center, left, right, up, down)
- Captures embeddings across multiple angles for robustness
- Secure Enclave encrypted storage

### Liveness Detection
- ARKit TrueDepth camera — same hardware as Face ID
- 5 randomised challenges: blink, turn left, turn right, smile, open mouth
- Hardware-level anti-spoofing — depth map + IR dot projection
- Photo attack resistant — detects flat surfaces
- Video replay resistant — blend shape muscle movement required

### Continuous Authentication
- Silent background face verification
- Instant blur when face leaves frame
- Instant unblur when face returns
- Identity check every 5 seconds
- Configurable session duration
- Different face detected → automatic lock

### Accuracy Pipeline
- **ArcFace R100** — ResNet100 backbone, trained on MS1MV2 + VGGFace2
- **Face Alignment** — C++ OpenCV warpAffine, canonical 112×112 eye positions
- **BiSeNet Segmentation** — 19-class neural face parsing
- **Retinex Illumination** — C++ single-scale, works in dark rooms
- **Multi-frame Averaging** — 5 frames averaged in C++
- **C++ Decision Engine** — sensor fusion (embedding + liveness + landmarks)

### Security
- Jailbreak detection
- Debugger detection
- Suspicious library detection (Frida, Substrate, Cycript)
- Checks disabled in DEBUG, enforced in RELEASE
- Secure Enclave key storage — biometric protected

---

## Architecture

```
FaceVault/
├── Core/          ← Pure C++ — shared iOS + Android
│   ├── FaceVaultMatcher       cosine similarity
│   ├── FaceVaultDecision      sensor fusion engine
│   ├── FaceVaultPreprocessor  crop + resize + normalize + IPD
│   ├── FaceVaultSegmentor     OpenCV ellipse segmentation
│   ├── FaceVaultAligner       face alignment warpAffine
│   ├── FaceVaultAgeEngine     age estimation logic
│   └── FaceVaultIntegrity     jailbreak + debugger detection
├── iOS/           ← Swift + Obj-C++ bridges
│   ├── FaceVault              main SDK orchestration
│   ├── FaceVaultCamera        AVFoundation 60fps
│   ├── FaceVaultVision        Vision Framework landmarks
│   ├── FaceVaultLiveness      ARKit blend shapes
│   ├── FaceVaultEmbedder      CoreML ArcFace R100
│   ├── FaceVaultStorage       Secure Enclave + Keychain
│   ├── FaceVaultPreviewView   Face ID style UI
│   ├── FaceVaultSegmentorML   BiSeNet CoreML
│   ├── FaceVaultAgeEstimator  age estimation Swift
│   └── FaceVaultContinuousAuth background face check
└── Models/
    ├── FaceVaultEmbedder.mlpackage    ArcFace R100 (99.77% LFW)
    ├── FaceVaultSegmentor.mlpackage   BiSeNet 19-class face parsing
    └── FaceVaultAgeEstimator.mlpackage MobileNetV2 age estimation
```

---

## Integration

### Requirements
- iOS 16+
- iPhone X or later (TrueDepth camera required)
- Xcode 15+

### Installation

1. Download `opencv2.framework` from [opencv.org](https://opencv.org/releases/) and add to `Frameworks/`
2. Add `FaceVault.xcframework` to your project
3. Add to `Info.plist`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>FaceVault uses Face ID to secure your biometric data</string>
<key>NSCameraUsageDescription</key>
<string>FaceVault uses the camera for face authentication</string>
```

### Usage

```swift
import FaceVault

let sdk = FaceVaultSDK()
sdk.attachPreview(previewView)

// Check enrollment
if sdk.isEnrolled() {
    // Authenticate
    sdk.authenticate { result in
        switch result {
        case .authenticated(let confidence):
            print("Authenticated — \(Int(confidence * 100))%")
            
        case .deniedNoMatch:
            print("Face does not match")
            
        case .deniedLiveness:
            print("Liveness check failed")
            
        case .deniedTampered:
            print("Security violation detected")
            
        default:
            break
        }
    }
} else {
    // Enroll first time
    sdk.enroll { success in
        if success {
            // Face enrolled — proceed to authenticate
        }
    }
}

// Continuous authentication
sdk.startContinuousAuth(interval: 5.0, maxDuration: 120.0) { event in
    switch event {
    case .faceVerified:  showContent()
    case .faceLost:      blurContent()
    case .faceChanged:   lockApp()
    case .multipleFaces: blurContent()
    }
}

// Logout
sdk.logout()
```

---

## FaceVault vs Server-Based SDKs

| Feature | FaceVault | Server-Based |
|---|---|---|
| On-device processing | ✅ 100% | ❌ Server |
| Works offline | ✅ | ❌ |
| Privacy | ✅ Zero data leaves device | ⚠️ Server processes face |
| GDPR by design | ✅ | ⚠️ Requires policy |
| Cost | ✅ Free | 💰 Per API call |
| Latency | ✅ < 200ms | ⚠️ Network dependent |
| Continuous auth | ✅ | ✅ |
| Liveness hardware | ✅ TrueDepth IR | ⚠️ Software only |
| Android ready | 🔜 C++ core ready | ✅ |
| Accuracy | ✅ 99.77% ArcFace R100 | Varies |

---

## Technical Highlights

**C++ Cross-Platform Core**  
All matching, alignment, segmentation, and decision logic written in pure C++. The iOS layer is a thin Swift/Obj-C++ bridge. Android port requires only JNI bindings — no logic rewrite.

**ArcFace R100**  
ResNet100 backbone trained with ArcFace loss on MS1MV2 + VGGFace2 (3.3M+ images). ArcFace loss maximises angular margin between face classes — significantly better at distinguishing similar faces versus standard metric learning approaches.

**ARKit TrueDepth Liveness**  
Uses the same TrueDepth camera system as Face ID — 30,000 IR dot projection + depth map + RGB. Detects:
- Photo printouts (flat depth map)
- Screen replay (no blend shape movement)
- 3D masks (IR reflection pattern)
- Silicone masks (depth + IR mismatch)

**Secure Enclave Storage**  
Face embedding encrypted with a Secure Enclave key that requires biometric authentication to access. Embedding never exists in plaintext in memory outside of the authentication flow.

---

## Author

**Ahmad Durrani**  
Senior iOS Engineer · MSc Computer Vision, Robotics & ML  
[GitHub](https://github.com/AhmadDurrani579) · [LinkedIn](https://www.linkedin.com/in/ahmad-yar-98990690)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

> **Note:** opencv2.framework is not included in this repository due to size (522MB).  
> Download from [opencv.org/releases](https://opencv.org/releases/) and add to `Frameworks/`.
