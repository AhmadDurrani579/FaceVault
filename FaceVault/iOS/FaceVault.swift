//
//  FaceVaultSDK.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//


import Foundation
import ARKit
import CoreMedia

// MARK: - Public Result
public enum FaceVaultResult {
    case authenticated(confidence: Float)
    case deniedNoMatch
    case deniedLiveness
    case deniedMultipleFaces
    case deniedInsufficientData
    case requiresRetry
}

// MARK: - FaceVaultSDK
public class FaceVaultSDK: NSObject {
    
    // MARK: - Components
    private let camera    = FaceVaultCamera()
    private let vision    = FaceVaultVision()
    private let embedder  = FaceVaultEmbedder()
    private let liveness  = FaceVaultLiveness()
    private let bridge    = FaceVaultMatcherBridge()
    private let storage   = FaceVaultStorage()
    
    // MARK: - State
    private var onResult: ((FaceVaultResult) -> Void)?
    private var enrollCompletion: ((Bool) -> Void)?
    private var currentEmbedding: [Float]?
    private var storedEmbedding: [Float]?
    private var landmarkCount: Int = 0
    private var livenessScore: Float = 0
    private var challengePassed: Bool = false
    private var singleFaceDetected: Bool = false
    private weak var previewView: FaceVaultPreviewView?
    private var lastEmbeddingTime: Date = .distantPast
    private var isEnrolling = false
    private var enrollCompleted = false
    private let preprocessor = FaceVaultPreprocessorBridge()
    private var lastLandmarks: FaceLandmarks?
    private var enrollEmbeddings: [[Float]] = []
    private let maxEnrollFrames = 10


    // MARK: - Init
    public override init() {
        super.init()
        vision.delegate   = self
        liveness.delegate = self
        warmUp()
    }
    
    private func warmUp() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 160, 160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            if let buffer = pixelBuffer {
                _ = self.embedder.generateEmbedding(from: buffer)
                print("✅ FaceVault: Model warmed up")
            }
        }
    }
    
    private func attachCameraPreview() {
        previewView?.attachCameraSession(camera.captureSession)
    }
    

    // MARK: - Public API
    public func enroll(completion: @escaping (Bool) -> Void) {
        #if targetEnvironment(simulator)
        completion(false)
        return
        #endif
        
        self.stop()
        
        isEnrolling = true
        enrollCompleted = false
        enrollCompletion = completion
        currentEmbedding = nil
        enrollEmbeddings = []
        
        previewView?.showMessage("🔐 Setting up secure storage...")
        
        // Face ID first
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = self.storage.deleteEmbedding()
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                self.previewView?.showMessage("Position your face in the oval")
                
                // Use ARKit — same as authenticate
                self.liveness.startEnrollMode() // no challenges, just frames
                self.attachLivenessPreview()
                
                // Countdown
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.previewView?.showMessage("Hold still... 3")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.previewView?.showMessage("Hold still... 2")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.previewView?.showMessage("Hold still... 1")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.finishEnroll(completion: completion)
                            }
                        }
                    }
                }
            }
        }
    }
    private func finishEnroll(completion: @escaping (Bool) -> Void) {
        camera.stop()
        
        guard !enrollEmbeddings.isEmpty else {
            previewView?.showMessage("❌ No face detected. Try again.")
            completion(false)
            return
        }
        
        // Average all collected embeddings
        let avgEmbedding = averageEmbeddings(enrollEmbeddings)
        
        // Save to Secure Enclave
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let saved = self.storage.saveEmbedding(avgEmbedding)
            self.storedEmbedding = avgEmbedding
            
            print(saved ? "✅ FaceVault: Face enrolled — \(self.enrollEmbeddings.count) frames averaged" : "❌ FaceVault: Save failed")
            
            DispatchQueue.main.async {
                completion(saved)
            }
        }
    }

    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        let size = embeddings[0].count
        var avg = [Float](repeating: 0, count: size)
        
        for embedding in embeddings {
            for i in 0..<size {
                avg[i] += embedding[i]
            }
        }
        
        let count = Float(embeddings.count)
        return avg.map { $0 / count }
    }


    
    public func authenticate(completion: @escaping (FaceVaultResult) -> Void) {
        #if targetEnvironment(simulator)
        completion(.deniedInsufficientData)
        return
        #endif
        
        self.stop()
        
        isEnrolling = false
        onResult = completion
        challengePassed = false
        livenessScore = 0
        currentEmbedding = nil
        
        // Show message BEFORE Face ID appears
        previewView?.showMessage("🔐 Authenticating with Face ID...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            guard let stored = self.storage.loadEmbedding() else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("❌ No enrolled face found")
                    completion(.deniedInsufficientData)
                }
                return
            }
            
            self.storedEmbedding = stored
            
            DispatchQueue.main.async {
                self.previewView?.showMessage("✅ Identity verified — scanning face...")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.liveness.start()
                    self.attachLivenessPreview()
                }
            }
        }
    }
    
    private func waitForEmbedding(retryCount: Int = 0, completion: @escaping ([Float]?) -> Void) {
            if let embedding = self.currentEmbedding {
                completion(embedding)
            } else if retryCount < 15 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.waitForEmbedding(retryCount: retryCount + 1, completion: completion)
                }
            } else {
                completion(nil)
            }
    }

    
    public func stop() {
        liveness.stop()
        camera.stop()
        
        // Clean up preview
        DispatchQueue.main.async {
            self.previewView?.reset()
        }
    }

    
    public func attachPreview(_ view: FaceVaultPreviewView) {
        previewView = view
    }
    
    private func attachLivenessPreview() {
        if let session = liveness.captureSession {
            previewView?.attachARSession(session)
        }
    }
    
    // MARK: - Decision
    private func makeDecision() {
        guard let current = currentEmbedding,
              let stored  = storedEmbedding else {
            DispatchQueue.main.async { [weak self] in
                self?.onResult?(.requiresRetry)
                self?.stop()
            }
            return
        }
        
        let nsA = current.map { NSNumber(value: $0) }
        let nsB = stored.map  { NSNumber(value: $0) }
        let embeddingScore = bridge.cosineSimilarity(nsA, b: nsB)
        
        print("📊 embeddingScore=\(embeddingScore) livenessScore=\(livenessScore) challengePassed=\(challengePassed) singleFace=\(singleFaceDetected) landmarks=\(landmarkCount)")

        let input = FaceVaultDecisionInput()
        input.embeddingScore     = embeddingScore
        input.livenessScore      = livenessScore
        input.challengePassed    = challengePassed
        input.singleFaceDetected = singleFaceDetected
        input.landmarkCount      = Int32(landmarkCount)
        
        let engine = FaceVaultDecisionBridge()
        let resultCode = engine.evaluate(input)
        print("🔍 resultCode = \(resultCode)")

        let faceVaultResult: FaceVaultResult
        switch resultCode {
        case 0: faceVaultResult = .authenticated(confidence: embeddingScore)
        case 1: faceVaultResult = .deniedLiveness
        case 2: faceVaultResult = .deniedNoMatch
        case 3: faceVaultResult = .deniedMultipleFaces
        case 4: faceVaultResult = .deniedInsufficientData
        default: faceVaultResult = .requiresRetry
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.onResult?(faceVaultResult)
        }
    }
}

// MARK: - Vision Delegate
extension FaceVaultSDK: FaceVaultVisionDelegate {
    public func vision(_ vision: FaceVaultVision, didDetect landmarks: FaceLandmarks) {
        singleFaceDetected = true
        landmarkCount = landmarks.landmarks.count
        lastLandmarks = landmarks
    }
    
    public func visionDidLoseFace(_ vision: FaceVaultVision) {
        singleFaceDetected = false
        landmarkCount = 0
        previewView?.showAngleWarning()
    }
    
    public func visionDidDetectMultipleFaces(_ vision: FaceVaultVision, count: Int) {
        singleFaceDetected = false
        DispatchQueue.main.async { [weak self] in
            self?.onResult?(.deniedMultipleFaces)
            self?.stop()
        }
    }
}

// MARK: - Liveness Delegate
extension FaceVaultSDK: FaceVaultLivenessDelegate {
    
    public func liveness(_ liveness: FaceVaultLiveness, didUpdate result: LivenessResult) {
            switch result {
            case .passed:
                challengePassed = true
                livenessScore = 1.0
                
                // Use the new non-blocking wait instead of Thread.sleep
                waitForEmbedding { [weak self] embedding in
                    guard let self = self, let validEmbedding = embedding else {
                        DispatchQueue.main.async {
                            self?.onResult?(.requiresRetry)
                            self?.stop()
                        }
                        return
                    }
                    
                    if self.isEnrolling {
                        guard !self.enrollCompleted else { return }
                        self.enrollCompleted = true
                        
                        let saved = self.storage.saveEmbedding(validEmbedding)
                        self.storedEmbedding = validEmbedding
                        
                        DispatchQueue.main.async {
                            self.stop()
                            self.enrollCompletion?(saved)
                        }
                    } else {
                        self.makeDecision()
                    }
                }
            
        case .failed(let reason):
            print("❌ FaceVault: Liveness failed — \(reason)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isEnrolling {
                    self.enrollCompletion?(false)
                } else {
                    self.onResult?(.deniedLiveness)
                }
                self.stop()
            }
            
        case .inProgress:
            break
        }
    }
    
    public func liveness(_ liveness: FaceVaultLiveness, requiresChallenge challenge: LivenessChallenge) {
        previewView?.showChallenge(challenge)
        print("🎯 FaceVault: Challenge required — \(challenge)")
    }
    
    public func liveness(_ liveness: FaceVaultLiveness, didCaptureFrame pixelBuffer: CVPixelBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastEmbeddingTime) > 0.5 else { return }
        lastEmbeddingTime = now
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            self.vision.process(pixelBuffer: pixelBuffer)
            
            guard let landmarks = self.lastLandmarks else { return }
            
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
            
            guard let result = self.preprocessor.process(pixelBuffer, faceRect: faceRect),
                  result.success else { return }
            
            if result.tooFar {
                DispatchQueue.main.async { self.previewView?.showMessage("📏 Move closer") }
                return
            }
            if result.tooClose {
                DispatchQueue.main.async { self.previewView?.showMessage("📏 Move further away") }
                return
            }
            
            let bufferToUse: CVPixelBuffer
            if let processed = result.processedBuffer {
                bufferToUse = processed
            } else {
                bufferToUse = pixelBuffer
            }
            
            guard let embedding = self.embedder.generateEmbedding(from: bufferToUse) else { return }
            
            if self.isEnrolling {
                // Store for averaging
                self.enrollEmbeddings.append(embedding)
                print("✅ FaceVault: Enroll frame \(self.enrollEmbeddings.count)/\(self.maxEnrollFrames)")
                DispatchQueue.main.async {
                    self.previewView?.showMessage("Scanning... \(self.enrollEmbeddings.count)/\(self.maxEnrollFrames)")
                }
            } else {
                // Auth mode
                self.currentEmbedding = embedding
            }
        }
    }
}

extension FaceVaultSDK: FaceVaultCameraDelegate {
    public func camera(_ camera: FaceVaultCamera, didOutput sampleBuffer: CMSampleBuffer) {
        guard isEnrolling else { return }
        guard enrollEmbeddings.count < maxEnrollFrames else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        vision.process(sampleBuffer: sampleBuffer)  // ← use sampleBuffer not pixelBuffer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            // Run Vision
            self.vision.process(pixelBuffer: pixelBuffer)
            
            guard let landmarks = self.lastLandmarks else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("👤 No face detected")
                }
                return
            }
            
            // ✅ Check 1 — Single face only
            guard self.singleFaceDetected else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Multiple faces detected")
                }
                return
            }
            
            // ✅ Check 2 — Head angle
            guard abs(landmarks.yaw)   < 0.3 &&
                  abs(landmarks.pitch) < 0.3 &&
                  abs(landmarks.roll)  < 0.3 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Face the camera directly")
                }
                return
            }
            
            // ✅ Check 3 — Enough landmarks
            guard landmarks.landmarks.count >= 50 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Poor face visibility")
                }
                return
            }
            
            // Build face rect
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
            
            // ✅ Check 4 — C++ preprocessor (distance + quality)
            guard let result = self.preprocessor.process(pixelBuffer, faceRect: faceRect) else {
                return
            }
            
            // ✅ Check 5 — Distance
            if result.tooFar {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("📏 Move closer")
                }
                return
            }
            
            if result.tooClose {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("📏 Move further away")
                }
                return
            }
            
            // ✅ Check 6 — Quality score
            guard result.qualityScore >= 0.5 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Poor image quality")
                }
                return
            }
            
            // ✅ Check 7 — Both eyes open
            // Eyes open = blink value LOW
            // We check via landmarks eye aspect ratio
            let leftEye  = landmarks.leftEye
            let rightEye = landmarks.rightEye
            let eyeDist  = sqrt(pow(rightEye.x - leftEye.x, 2) +
                               pow(rightEye.y - leftEye.y, 2))
            guard eyeDist > 0.05 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("👁 Please open both eyes")
                }
                return
            }
            
            // ✅ All checks passed — generate embedding
            guard result.success else { return }
            
            guard let processedBuffer = result.processedBuffer else {
                // Fallback to original
                guard let embedding = self.embedder.generateEmbedding(from: pixelBuffer) else { return }
                self.enrollEmbeddings.append(embedding)
                return
            }

            guard let embedding = self.embedder.generateEmbedding(from: processedBuffer) else { return }
            self.enrollEmbeddings.append(embedding)

            let count = self.enrollEmbeddings.count
            print("✅ FaceVault: Enroll frame \(count)/\(self.maxEnrollFrames)")
            
            DispatchQueue.main.async {
                self.previewView?.showMessage("✅ Scanning \(count)/\(self.maxEnrollFrames)")
            }
        }
    }
}
