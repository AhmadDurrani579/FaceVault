//
//  FaceVaultPreviewView.swift
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

import UIKit
import ARKit
import AVFoundation

public class FaceVaultPreviewView: UIView {
    
    private let sceneView = ARSCNView()
    private let instructionLabel = UILabel()
    private var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
    private var landmarkDots: [CAShapeLayer] = []
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let warningLabel = UILabel()
    public let faceOvalLayer = CAShapeLayer()
    private var segmentLayers: [CAShapeLayer] = []
    private let totalSegments = 40

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .black
        
        sceneView.frame = bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.automaticallyUpdatesLighting = false
        sceneView.rendersCameraGrain = false
        addSubview(sceneView)
        
        // Thin oval guide
//        faceOvalLayer.fillColor = UIColor.clear.cgColor
//        faceOvalLayer.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
//        faceOvalLayer.lineWidth = 1
//        layer.addSublayer(faceOvalLayer)
        
        // Blur view
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.alpha = 0
        addSubview(blurView)
        
        warningLabel.text = "⚠️ Multiple faces detected"
        warningLabel.textColor = .white
        warningLabel.textAlignment = .center
        warningLabel.font = .systemFont(ofSize: 20, weight: .bold)
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(warningLabel)
        NSLayoutConstraint.activate([
            warningLabel.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            warningLabel.centerYAnchor.constraint(equalTo: blurView.centerYAnchor)
        ])
        
        // Instruction label
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -100),
            instructionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        
//        // Oval guide — slightly inside the segments
//        let ovalRect = CGRect(
//            x: bounds.midX - 120,
//            y: bounds.midY - 160,
//            width: 240,
//            height: 320
//        )
//        faceOvalLayer.path = UIBezierPath(ovalIn: ovalRect).cgPath
        
        // Rebuild segments
        setupProgressRing()
    }
    
    // MARK: - Progress Ring (Apple Face ID style)
    private func setupProgressRing() {
        segmentLayers.forEach { $0.removeFromSuperlayer() }
        segmentLayers.removeAll()
        
        let totalAngle = 2.0 * CGFloat.pi
        let segmentAngle = totalAngle / CGFloat(totalSegments)
        let gap = segmentAngle * 0.2
        
        // Oval dimensions — match face shape
        let rx: CGFloat = 140  // horizontal radius
        let ry: CGFloat = 185  // vertical radius — taller for face
        let cx = bounds.midX
        let cy = bounds.midY
        
        for i in 0..<totalSegments {
            let startAngle = CGFloat(i) * segmentAngle - .pi / 2
            let endAngle = startAngle + segmentAngle - gap
            
            // Draw oval arc using bezier path
            let path = UIBezierPath()
            let steps = 10
            
            for step in 0...steps {
                let angle = startAngle + (endAngle - startAngle) * CGFloat(step) / CGFloat(steps)
                let x = cx + rx * cos(angle)
                let y = cy + ry * sin(angle)
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            let segment = CAShapeLayer()
            segment.path = path.cgPath
            segment.fillColor = UIColor.clear.cgColor
            segment.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
            segment.lineWidth = 8
            segment.lineCap = .round
            layer.addSublayer(segment)
            segmentLayers.append(segment)
        }
    }
    
    public func updateProgress(_ progress: Float) {
        DispatchQueue.main.async {
            let filledCount = Int(Float(self.totalSegments) * progress)
            
            for (i, segment) in self.segmentLayers.enumerated() {
                let shouldFill = i < filledCount
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.5)
                CATransaction.setAnimationTimingFunction(
                    CAMediaTimingFunction(name: .easeInEaseOut))
                segment.strokeColor = shouldFill ?
                    UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0).cgColor :
                    UIColor.white.withAlphaComponent(0.2).cgColor
                CATransaction.commit()
            }
        }
    }
    
    public func resetProgress() {
        DispatchQueue.main.async {
            self.segmentLayers.forEach {
                $0.strokeColor = UIColor.white.withAlphaComponent(0.2).cgColor
            }
        }
    }
    
    // MARK: - Landmarks
    public func updateLandmarks(_ landmarks: [CGPoint], boundingBox: CGRect) {
        DispatchQueue.main.async {
            self.landmarkDots.forEach { $0.removeFromSuperlayer() }
            self.landmarkDots.removeAll()
            
            for point in landmarks {
                let viewX = boundingBox.origin.x * self.bounds.width
                           + point.x * boundingBox.width * self.bounds.width
                let viewY = (1 - boundingBox.origin.y) * self.bounds.height
                           - point.y * boundingBox.height * self.bounds.height
                
                let dot = CAShapeLayer()
                let dotSize: CGFloat = 3
                dot.path = UIBezierPath(ovalIn: CGRect(
                    x: viewX - dotSize/2,
                    y: viewY - dotSize/2,
                    width: dotSize,
                    height: dotSize)).cgPath
                dot.fillColor = UIColor.green.withAlphaComponent(0.8).cgColor
                self.layer.addSublayer(dot)
                self.landmarkDots.append(dot)
            }
        }
    }
    
    public func clearLandmarks() {
        DispatchQueue.main.async {
            self.landmarkDots.forEach { $0.removeFromSuperlayer() }
            self.landmarkDots.removeAll()
        }
    }
    
    // MARK: - Multiple Faces
    public func showMultipleFacesWarning() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                self.blurView.alpha = 1
            }
            self.segmentLayers.forEach {
                $0.strokeColor = UIColor.red.withAlphaComponent(0.6).cgColor
            }
            self.clearLandmarks()
        }
    }
    
    public func hideMultipleFacesWarning() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                self.blurView.alpha = 0
            }
        }
    }
    
    // MARK: - Sessions
    public func attachARSession(_ session: ARSession) {
        DispatchQueue.main.async {
            self.cameraPreviewLayer?.removeFromSuperlayer()
            self.cameraPreviewLayer = nil
            self.sceneView.isHidden = false
            self.sceneView.session = session
            // Make sure sceneView is behind segments
            self.sendSubviewToBack(self.sceneView)
        }

    }
    
    public func attachCameraSession(_ session: AVCaptureSession) {
        DispatchQueue.main.async {
            self.sceneView.isHidden = true
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.bounds
            self.layer.insertSublayer(layer, at: 0)
            self.cameraPreviewLayer = layer
        }
    }
    
    // MARK: - Messages
    public func showChallenge(_ challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                self.instructionLabel.alpha = 0
            } completion: { _ in
                self.instructionLabel.text = challenge.instruction
                UIView.animate(withDuration: 0.3) {
                    self.instructionLabel.alpha = 1
                }
            }
        }
    }
    
    public func showMessage(_ message: String) {
        DispatchQueue.main.async {
            self.instructionLabel.text = message
        }
    }
    
    public func showAngleWarning() {
        DispatchQueue.main.async {
            self.instructionLabel.text = "⚠️ Please face the camera directly"
            self.segmentLayers.forEach {
                $0.strokeColor = UIColor.orange.withAlphaComponent(0.4).cgColor
            }
        }
    }
    
    public func reset() {
        cameraPreviewLayer?.removeFromSuperlayer()
        cameraPreviewLayer = nil
        sceneView.isHidden = true
        instructionLabel.text = ""
        resetProgress()
        clearLandmarks()
        hideMultipleFacesWarning()
    }
}

// MARK: - Challenge Instructions
extension LivenessChallenge {
    public var instruction: String {
        switch self {
        case .blink:      return "👁 Blink both eyes"
        case .turnLeft:   return "⬅️ Turn your head left"
        case .turnRight:  return "➡️ Turn your head right"
        case .smile:      return "😊 Smile"
        case .openMouth:  return "😮 Open your mouth"
        }
    }
}
