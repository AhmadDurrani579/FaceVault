//
//  ViewController.swift
//  FaceVaultDemo
//
//  Created by Ahmad on 24/03/2026.
//

import UIKit
import FaceVault

class ViewController: UIViewController {
    let sdk = FaceVaultSDK()
    let previewView = FaceVaultPreviewView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreview()
        startEnrollment()
        // Do any additional setup after loading the view.
    }
    
    private func setupPreview() {
        previewView.frame = view.bounds
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewView)
        sdk.attachPreview(previewView)
    }
    
    private func startEnrollment() {
        previewView.showMessage("Position your face in the oval")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.sdk.enroll { success in
                DispatchQueue.main.async {
                    if success {
                        self.previewView.showMessage("✅ Face enrolled! Authenticating...")
                        self.startAuthentication()
                    } else {
                        self.previewView.showMessage("❌ Enrollment failed. Try again.")
                    }
                }
            }
        }
    }
    
    private func startAuthentication() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sdk.authenticate { result in
                DispatchQueue.main.async {
                    switch result {
                    case .authenticated(let confidence):
                        self.previewView.showMessage("✅ Authenticated! (\(Int(confidence * 100))%)")
                    case .deniedNoMatch:
                        self.previewView.showMessage("❌ Face does not match")
                    case .deniedLiveness:
                        self.previewView.showMessage("❌ Liveness check failed")
                    case .deniedMultipleFaces:
                        self.previewView.showMessage("❌ Multiple faces detected")
                    case .deniedInsufficientData:
                        self.previewView.showMessage("❌ No enrolled face found")
                    case .requiresRetry:
                        self.previewView.showMessage("🔄 Please try again")
                    }
                }
            }
        }
    }


}

