//
//  FaceVaultLiveness.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import ARKit
import Foundation

// MARK: - Challenge Types
public enum LivenessChallenge {
    case blink
    case turnLeft
    case turnRight
    case smile
    case openMouth
}

// MARK: - Liveness Result
public enum LivenessResult {
    case passed
    case failed(reason: String)
    case inProgress(challenge: LivenessChallenge)
}

// MARK: - Delegate
public protocol FaceVaultLivenessDelegate: AnyObject {
    func liveness(_ liveness: FaceVaultLiveness, didUpdate result: LivenessResult)
    func liveness(_ liveness: FaceVaultLiveness, requiresChallenge challenge: LivenessChallenge)
}

// MARK: - FaceVaultLiveness
public class FaceVaultLiveness: NSObject {
    
    // MARK: - Properties
    private var arSession: ARSession?
    public weak var delegate: FaceVaultLivenessDelegate?
    
    private var currentChallenge: LivenessChallenge?
    private var challengeStartTime: Date?
    private let challengeTimeout: TimeInterval = 5.0
    
    // Blend shape thresholds
    private let blinkThreshold: Float        = 0.8
    private let smileThreshold: Float        = 0.6
    private let turnThreshold: Float         = 0.3
    private let openMouthThreshold: Float    = 0.5
    
    // Challenge sequence
    private var challengeQueue: [LivenessChallenge] = []
    private var completedChallenges: [LivenessChallenge] = []
    
    public private(set) var isRunning = false
    
    // MARK: - Init
    public override init() {
        super.init()
    }
    
    // MARK: - Start
    public func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("FaceVault: ARKit face tracking not supported on this device")
            return
        }
        arSession = ARSession()
        arSession?.delegate = self
        
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        arSession?.run(config)
        
        isRunning = true
        generateChallengeQueue()
        print("FaceVault: Liveness session started")
    }
    
    // MARK: - Stop
    public func stop() {
        arSession?.pause()
        arSession = nil
        isRunning = false
        print("FaceVault: Liveness session stopped")
    }
    
    // MARK: - Generate Random Challenge Queue
    private func generateChallengeQueue() {
        let all: [LivenessChallenge] = [.blink, .turnLeft, .turnRight, .smile, .openMouth]
        challengeQueue = all.shuffled().prefix(3).map { $0 }
        completedChallenges = []
        startNextChallenge()
    }
    
    private func startNextChallenge() {
        guard let next = challengeQueue.first else {
            // All challenges passed
            delegate?.liveness(self, didUpdate: .passed)
            print("FaceVault: All liveness challenges passed!")
            return
        }
        
        currentChallenge = next
        challengeStartTime = Date()
        challengeQueue.removeFirst()
        
        delegate?.liveness(self, requiresChallenge: next)
        delegate?.liveness(self, didUpdate: .inProgress(challenge: next))
        print("FaceVault: Challenge started — \(next)")
    }
    
    // MARK: - Evaluate Blend Shapes
    private func evaluate(blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) {
        guard let challenge = currentChallenge,
              let startTime = challengeStartTime else { return }
        
        // Check timeout
        if Date().timeIntervalSince(startTime) > challengeTimeout {
            delegate?.liveness(self, didUpdate: .failed(reason: "Challenge timed out"))
            print("FaceVault: Challenge timed out")
            stop()
            return
        }
        
        var passed = false
        
        switch challenge {
        case .blink:
            let leftBlink  = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
            let rightBlink = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
            passed = leftBlink > blinkThreshold && rightBlink > blinkThreshold
            
        case .turnLeft:
            let jaw = blendShapes[.jawLeft]?.floatValue ?? 0
            passed = jaw > turnThreshold
            
        case .turnRight:
            let jaw = blendShapes[.jawRight]?.floatValue ?? 0
            passed = jaw > turnThreshold
            
        case .smile:
            let smileLeft  = blendShapes[.mouthSmileLeft]?.floatValue ?? 0
            let smileRight = blendShapes[.mouthSmileRight]?.floatValue ?? 0
            passed = smileLeft > smileThreshold && smileRight > smileThreshold
            
        case .openMouth:
            let jawOpen = blendShapes[.jawOpen]?.floatValue ?? 0
            passed = jawOpen > openMouthThreshold
        }
        
        if passed {
            completedChallenges.append(challenge)
            currentChallenge = nil
            print("FaceVault: Challenge passed — \(challenge)")
            startNextChallenge()
        }
    }
}

// MARK: - ARSession Delegate
extension FaceVaultLiveness: ARSessionDelegate {
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        evaluate(blendShapes: faceAnchor.blendShapes)
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        print(" FaceVault: ARSession failed — \(error)")
        delegate?.liveness(self, didUpdate: .failed(reason: error.localizedDescription))
    }
}
