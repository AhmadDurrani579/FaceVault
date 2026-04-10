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
    private let whiteOverlay = UIView()
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    private var meshPoints: [CGPoint] = []
    private var meshLayer = CAShapeLayer()
    
    private let topLeftBracket = CAShapeLayer()
    private let topRightBracket = CAShapeLayer()
    private let bottomLeftBracket = CAShapeLayer()
    private let bottomRightBracket = CAShapeLayer()

    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .white
        
        // ARKit camera — full screen behind
        sceneView.frame = bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.automaticallyUpdatesLighting = false
        sceneView.rendersCameraGrain = false
        addSubview(sceneView)
        
        // White overlay — covers everything outside oval
        whiteOverlay.backgroundColor = .white
        whiteOverlay.frame = bounds
        whiteOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(whiteOverlay)
        
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
        
        // Instruction label — dark text for white background
        
        // Title label
        titleLabel.text = "Face Enrollment"
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 80),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])

        // Subtitle label
        subtitleLabel.text = "Position your face in the frame"
        subtitleLabel.textColor = .darkGray
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40)
        ])
        
        instructionLabel.textColor = .darkGray
        instructionLabel.textAlignment = .center
        instructionLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -140), // ← move up
            instructionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            instructionLabel.heightAnchor.constraint(equalToConstant: 44),
            instructionLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -80)
        ])

        meshLayer.strokeColor = UIColor(red: 0, green: 1, blue: 0.5, alpha: 0.7).cgColor
        meshLayer.fillColor = UIColor.clear.cgColor
        meshLayer.lineWidth = 0.8
        layer.addSublayer(meshLayer)
    }
    
    public func showEnrollmentUI() {
        DispatchQueue.main.async {
            self.titleLabel.isHidden = false
            self.subtitleLabel.isHidden = false
            self.whiteOverlay.isHidden = false
            self.backgroundColor = .white
            self.instructionLabel.textColor = .darkGray
            
            // Hide mesh and brackets
            self.meshLayer.isHidden = true
            self.topLeftBracket.path = nil
            self.topRightBracket.path = nil
            self.bottomLeftBracket.path = nil
            self.bottomRightBracket.path = nil
        }
    }


    public func showAuthenticationUI() {
        DispatchQueue.main.async {
            self.titleLabel.isHidden = true
            self.subtitleLabel.isHidden = true
            self.whiteOverlay.isHidden = true
            self.backgroundColor = .black
            self.sceneView.isHidden = false
            self.instructionLabel.textColor = .white
            
            // Show corner brackets
            self.setupCornerBrackets()
            self.updateCornerBrackets()
            
            // Show mesh layer
            self.meshLayer.isHidden = false
        }
    }

    
    private func setupCornerBrackets() {
        let brackets = [topLeftBracket, topRightBracket,
                        bottomLeftBracket, bottomRightBracket]
        brackets.forEach {
            $0.strokeColor = UIColor(red: 0, green: 1, blue: 0.5, alpha: 1).cgColor
            $0.fillColor = UIColor.clear.cgColor
            $0.lineWidth = 3
            $0.lineCap = .round
            layer.addSublayer($0)
        }
    }
    
    private func updateCornerBrackets() {
        let margin: CGFloat = 40
        let length: CGFloat = 40
        let x1 = margin
        let y1 = margin + 60
        let x2 = bounds.width - margin
        let y2 = bounds.height - margin - 60
        
        // Top left
        let tl = UIBezierPath()
        tl.move(to: CGPoint(x: x1, y: y1 + length))
        tl.addLine(to: CGPoint(x: x1, y: y1))
        tl.addLine(to: CGPoint(x: x1 + length, y: y1))
        topLeftBracket.path = tl.cgPath
        
        // Top right
        let tr = UIBezierPath()
        tr.move(to: CGPoint(x: x2 - length, y: y1))
        tr.addLine(to: CGPoint(x: x2, y: y1))
        tr.addLine(to: CGPoint(x: x2, y: y1 + length))
        topRightBracket.path = tr.cgPath
        
        // Bottom left
        let bl = UIBezierPath()
        bl.move(to: CGPoint(x: x1, y: y2 - length))
        bl.addLine(to: CGPoint(x: x1, y: y2))
        bl.addLine(to: CGPoint(x: x1 + length, y: y2))
        bottomLeftBracket.path = bl.cgPath
        
        // Bottom right
        let br = UIBezierPath()
        br.move(to: CGPoint(x: x2 - length, y: y2))
        br.addLine(to: CGPoint(x: x2, y: y2))
        br.addLine(to: CGPoint(x: x2 - length, y: y2))
        br.move(to: CGPoint(x: x2, y: y2 - length))
        br.addLine(to: CGPoint(x: x2, y: y2))
        bottomRightBracket.path = br.cgPath
    }


    public override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        whiteOverlay.frame = bounds
        meshLayer.frame = bounds
        
        // Update oval cutout
        let ovalRect = CGRect(
            x: bounds.midX - 150,
            y: bounds.midY - 200,
            width: 300,
            height: 400
        )
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: ovalRect)
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
        whiteOverlay.layer.mask = maskLayer
        
        updateCornerBrackets()
        setupProgressRing()
    }
    
    public func updateMesh(points: [CGPoint]) {
        DispatchQueue.main.async {
            guard points.count > 10 else { return }
            
            let path = UIBezierPath()
            
            // Only connect points that are close together
            // Max distance = 30px
            let maxDistance: CGFloat = 20
            
            for i in 0..<points.count {
                for j in i+1..<points.count {
                    let dx = points[i].x - points[j].x
                    let dy = points[i].y - points[j].y
                    let dist = sqrt(dx*dx + dy*dy)
                    
                    if dist < maxDistance {
                        path.move(to: points[i])
                        path.addLine(to: points[j])
                    }
                }
            }
            
            self.meshLayer.path = path.cgPath
        }
    }

    public func clearMesh() {
        DispatchQueue.main.async {
            self.meshLayer.path = nil
        }
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
            UIView.animate(withDuration: 0.2) {
                self.instructionLabel.alpha = 0
            } completion: { _ in
                self.instructionLabel.text = "  \(challenge.instruction)  "
                self.instructionLabel.textColor = .white
                self.instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
                self.instructionLabel.layer.cornerRadius = 22  // ← full pill
                self.instructionLabel.layer.masksToBounds = true
                self.instructionLabel.font = .systemFont(ofSize: 16, weight: .semibold)
                UIView.animate(withDuration: 0.2) {
                    self.instructionLabel.alpha = 1
                }
            }
        }
    }
    
    public func showMessage(_ message: String) {
        DispatchQueue.main.async {
            self.instructionLabel.text = "  \(message)  "
            self.instructionLabel.layer.cornerRadius = 22
            self.instructionLabel.layer.masksToBounds = true
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
