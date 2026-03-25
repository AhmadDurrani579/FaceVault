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
        
        // Show message BEFORE Face ID appears
        previewView?.showMessage("🔐 Setting up secure storage...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            
            DispatchQueue.global(qos: .userInitiated).async {
                _ = self.storage.deleteEmbedding()
                
                DispatchQueue.main.async {
                    self.previewView?.showMessage("✅ Secure storage ready — position your face")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.liveness.start()
                        self.attachLivenessPreview()
                    }
                }
            }
        }
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
            
            // Run Vision first
            self.vision.process(pixelBuffer: pixelBuffer)
            
            // Use C++ preprocessor if we have landmarks
            if let landmarks = self.lastLandmarks {
                let faceRect = FaceVaultFaceRect()
                faceRect.x             = Float(landmarks.boundingBox.origin.x)
                faceRect.y             = Float(landmarks.boundingBox.origin.y)
                faceRect.width         = Float(landmarks.boundingBox.size.width)
                faceRect.height        = Float(landmarks.boundingBox.size.height)
                faceRect.yaw           = landmarks.yaw
                faceRect.pitch         = landmarks.pitch
                faceRect.roll          = landmarks.roll
                faceRect.landmarkCount = Int32(landmarks.landmarks.count)
                
                if  let result = self.preprocessor.process(pixelBuffer, faceRect: faceRect) {
                    if result.success {
                        print("✅ FaceVault: Preprocessed — quality: \(result.qualityScore)")
                        // Generate embedding from preprocessed face
                        self.currentEmbedding = self.embedder.generateEmbedding(from: pixelBuffer)
                    } else {
                        print("⚠️ FaceVault: Preprocess failed — \(result.error ?? "unknown")")
                    }
                }
            } else {
                // Fallback — no landmarks yet
                self.currentEmbedding = self.embedder.generateEmbedding(from: pixelBuffer)
            }
        }
    }
}
