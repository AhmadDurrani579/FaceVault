//
//  FaceVaultPreviewView.swift
//  FaceVault
//
//  Created by Ahmad on 25/03/2026.
//

import UIKit
import ARKit

public class FaceVaultPreviewView: UIView {
    
    private let sceneView = ARSCNView()
    private let instructionLabel = UILabel()
    private let faceOvalLayer = CAShapeLayer()
    
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
        
        // ARSCNView as preview
        sceneView.frame = bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.automaticallyUpdatesLighting = false
        sceneView.rendersCameraGrain = false
        addSubview(sceneView)
        
        // Face oval
        faceOvalLayer.fillColor = UIColor.clear.cgColor
        faceOvalLayer.strokeColor = UIColor.white.cgColor
        faceOvalLayer.lineWidth = 3
        layer.addSublayer(faceOvalLayer)
        
        // Instruction label
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        instructionLabel.numberOfLines = 0
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.layer.masksToBounds = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -80),
            instructionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -20),
            instructionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        
        let ovalRect = CGRect(
            x: bounds.midX - 140,
            y: bounds.midY - 180,
            width: 280,
            height: 360
        )
        faceOvalLayer.path = UIBezierPath(ovalIn: ovalRect).cgPath
    }
    
    // MARK: - Public
    public func attachARSession(_ session: ARSession) {
        DispatchQueue.main.async {
            self.sceneView.session = session
        }
    }
    
    public func showChallenge(_ challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                self.instructionLabel.alpha = 0
            } completion: { _ in
                self.instructionLabel.text = "  \(challenge.instruction)  "
                UIView.animate(withDuration: 0.3) {
                    self.instructionLabel.alpha = 1
                }
            }
        }
    }
    
    public func showMessage(_ message: String) {
        DispatchQueue.main.async {
            self.instructionLabel.text = "  \(message)  "
        }
    }
    
    public func showAngleWarning() {
        DispatchQueue.main.async {
            self.instructionLabel.text = "  ⚠️ Please face the camera directly  "
        }
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
