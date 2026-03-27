//
//  FaceVaultContinuousAuth.swift
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//


import AVFoundation
import Vision
import CoreMedia

public enum ContinuousAuthEvent {
    case faceVerified(confidence: Float)
    case faceLost
    case faceChanged(confidence: Float)
    case multipleFaces
}

// MARK: - Delegate
public protocol FaceVaultContinuousAuthDelegate: AnyObject {
    func continuousAuth(_ auth: FaceVaultContinuousAuth,
                        didDetect event: ContinuousAuthEvent)
}

// MARK: - ContinuousAuth
public class FaceVaultContinuousAuth: NSObject {
    
    // MARK: - Properties
    private let camera     = FaceVaultCamera()
    private let vision     = FaceVaultVision()
    private let embedder   = FaceVaultEmbedder()
    private let bridge     = FaceVaultMatcherBridge()
    private let preprocessor = FaceVaultPreprocessorBridge()
    
    public weak var delegate: FaceVaultContinuousAuthDelegate?
    
    private var storedEmbedding: [Float]?
    private var checkInterval: TimeInterval = 5.0
    private var matchThreshold: Float = 0.75
    private var timer: Timer?
    private var isRunning = false
    private var lastLandmarks: FaceLandmarks?
    public var onStopped: (() -> Void)?
    private var isChecking = false
    private var faceLostTimer: Timer?
    private var consecutiveLostCount = 0

    // MARK: - Init
    public override init() {
        super.init()
        vision.delegate = self
        camera.delegate = self
    }
    
    // MARK: - Public API
    public func start(storedEmbedding: [Float],
                      interval: TimeInterval = 5.0,
                      threshold: Float = 0.75,
                      maxDuration: TimeInterval) {
        
        print("✅ FaceVault: Continuous auth started — interval:\(interval)s max:\(maxDuration)s")

        self.storedEmbedding = storedEmbedding
        self.checkInterval   = interval
        self.matchThreshold  = threshold
        self.isRunning       = true
        
        camera.start()
        
        DispatchQueue.main.async {
            // Check timer
            self.timer = Timer.scheduledTimer(
                timeInterval: interval,
                target: self,
                selector: #selector(self.performCheck),
                userInfo: nil,
                repeats: true
            )
            
            // Auto stop after maxDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) {
                [weak self] in
                guard let self, self.isRunning else { return }
                print("⏱ FaceVault: Continuous auth ended — 2 minutes")
                self.stop()
            }
        }
        
        print("✅ FaceVault: Continuous auth started — interval:\(interval)s max:\(maxDuration)s")
    }
    
    
    public func stop() {
        guard isRunning else { return }  // ← prevent double stop
        isRunning = false
        timer?.invalidate()
        timer = nil
        camera.stop()
        print("✅ FaceVault: Continuous auth stopped")
        DispatchQueue.main.async {
            self.onStopped?()  // ← make sure this fires
        }
    }

    
    // MARK: - Check
    @objc private func performCheck() {
        guard isRunning, !isChecking else { return }
        isChecking = true
        print("🔄 FaceVault: Continuous auth check...")
        // Frame will come through camera delegate
    }
    
    private func checkFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRunning, isChecking else { return }
        guard let stored = storedEmbedding else { return }
        
        // Copy pixel buffer
        var copyBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &copyBuffer
        )
        
        guard let safeCopy = copyBuffer else {
            isChecking = false
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(safeCopy, CVPixelBufferLockFlags(rawValue: 0))
        
        let src = CVPixelBufferGetBaseAddress(pixelBuffer)
        let dst = CVPixelBufferGetBaseAddress(safeCopy)
        let size = CVPixelBufferGetDataSize(pixelBuffer)
        
        if let src, let dst { memcpy(dst, src, size) }
        
        CVPixelBufferUnlockBaseAddress(safeCopy, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.isChecking = false // ← always release lock
                }
            }
            
            self.vision.process(pixelBuffer: safeCopy, orientation: .up, maxAngle: 0.7)
            
            guard let landmarks = self.lastLandmarks else {
                self.consecutiveLostCount += 1
                print("⚠️ FaceVault: Continuous — no face (\(self.consecutiveLostCount)/3)")
                DispatchQueue.main.async {
//                    self.delegate?.continuousAuth(self, didDetect: .faceLost) // ← instant
                    self.isChecking = false
                }
                return

//                // Only fire faceLost after 3 consecutive misses
//                if self.consecutiveLostCount >= 3 {
//                    self.consecutiveLostCount = 0
//                    DispatchQueue.main.async {
//                        self.delegate?.continuousAuth(self, didDetect: .faceLost)
//                    }
//                }
//                return
            }
            
            // Face found — reset counter
            self.consecutiveLostCount = 0
            
            let faceRect = FaceVaultFaceRect()
            faceRect.x             = Float(landmarks.boundingBox.origin.x)
            faceRect.y             = Float(landmarks.boundingBox.origin.y)
            faceRect.width         = Float(landmarks.boundingBox.size.width)
            faceRect.height        = Float(landmarks.boundingBox.size.height)
            faceRect.yaw           = landmarks.yaw
            faceRect.pitch         = landmarks.pitch
            faceRect.roll          = landmarks.roll
            faceRect.landmarkCount = Int32(landmarks.landmarks.count)
            faceRect.leftEyeX      = Float(landmarks.leftEye.x)
            faceRect.leftEyeY      = Float(landmarks.leftEye.y)
            faceRect.rightEyeX     = Float(landmarks.rightEye.x)
            faceRect.rightEyeY     = Float(landmarks.rightEye.y)
            
            guard let result = self.preprocessor.process(safeCopy, faceRect: faceRect),
                  result.success,
                  let processedBuffer = result.processedBuffer else {
                DispatchQueue.main.async {
                    self.delegate?.continuousAuth(self, didDetect: .faceLost)
                }
                return
            }
            
            guard let embedding = self.embedder.generateEmbedding(from: processedBuffer) else {
                return
            }
            
            let nsA = embedding.map { NSNumber(value: $0) }
            let nsB = stored.map   { NSNumber(value: $0) }
            let score = self.bridge.cosineSimilarity(nsA, b: nsB)
            
            print("🔄 FaceVault: Continuous check — score: \(score)")
            
            DispatchQueue.main.async {
                if score >= self.matchThreshold {
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceVerified(confidence: score))
                } else {
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceChanged(confidence: score))
                }
            }
        }
    }
}

// MARK: - Camera Delegate
extension FaceVaultContinuousAuth: FaceVaultCameraDelegate {
    public func camera(_ camera: FaceVaultCamera,
                       didOutput sampleBuffer: CMSampleBuffer) {
        guard isRunning, isChecking else { return } // ← only when check needed
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        checkFrame(pixelBuffer)
    }
}

// MARK: - Vision Delegate
extension FaceVaultContinuousAuth: FaceVaultVisionDelegate {
    public func vision(_ vision: FaceVaultVision, didDetect landmarks: FaceLandmarks) {
        // Instant unblur
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .faceVerified(confidence: 1.0))
        }
    }
    
    public func visionDidLoseFace(_ vision: FaceVaultVision) {
        // Instant blur
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .faceLost)
        }
    }
    
    public func visionDidDetectMultipleFaces(_ vision: FaceVaultVision, count: Int) {
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .multipleFaces)
        }
    }
}

