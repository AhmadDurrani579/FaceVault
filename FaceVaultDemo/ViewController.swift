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
        
        // Show loading first
        previewView.showMessage("Loading FaceVault...")
        
        // Wait for warmup then start
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.startEnrollment()
        }
        // Do any additional setup after loading the view.
    }
    
    private func setupPreview() {
        previewView.frame = view.bounds
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewView)
        sdk.attachPreview(previewView)
    }
    
    private func blurScreen(_ blur: Bool) {
        DispatchQueue.main.async {
            if blur {
                let blurEffect = UIBlurEffect(style: .dark)
                let blurView = UIVisualEffectView(effect: blurEffect)
                blurView.frame = self.view.bounds
                blurView.tag = 999
                self.view.addSubview(blurView)
                
                let label = UILabel()
                label.text = "👁 Face required to continue"
                label.textColor = .white
                label.textAlignment = .center
                label.font = .systemFont(ofSize: 18, weight: .semibold)
                label.frame = blurView.bounds
                blurView.contentView.addSubview(label)
            } else {
                self.view.viewWithTag(999)?.removeFromSuperview()
            }
        }
    }

    private func lockApp() {
        DispatchQueue.main.async {
            self.sdk.stopContinuousAuth()
            self.blurScreen(false)
            self.previewView.isHidden = false
            self.previewView.showMessage("🔒 Session expired — please re-authenticate")
            // Re-authenticate
//            self.startAuthentication()
        }
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
                        self.previewView.showMessage("✅ Authenticated! \(Int(confidence * 100))%")
                        
                        // Test age estimation
                        self.sdk.estimateAge { result in
                            if let result = result {
                                print("👤 Age: \(result.estimatedAge)")
                                print("👤 Range: \(result.ageRange)")
                                print("👤 IsAdult: \(result.isAdult)")
                                print("👤 Confidence: \(result.confidence)")
                                self.previewView.showMessage("✅ Auth \(Int(confidence * 100))% | Age: ~\(Int(result.estimatedAge))")
                            }
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.previewView.isHidden = true
                            
                            // Start continuous auth
                            self.sdk.startContinuousAuth(interval: 1.0, maxDuration: 120.0)  { event in
                                switch event {
                                case .faceVerified(let score):
                                    self.blurScreen(false) // ← hide blur when face returns

                                    print("✅ Continuous: Face verified — \(score)")
                                    
                                case .faceLost:
                                    print("⚠️ Continuous: Face lost — blurring")
                                    self.blurScreen(true)
                                    
                                case .faceChanged(let score):
                                    print("❌ Continuous: Different face — \(score)")
                                    self.lockApp()
                                    
                                case .multipleFaces:
                                    print("⚠️ Continuous: Multiple faces")
                                    self.blurScreen(true)
                                }
                            }
                            
                            self.sdk.onContinuousAuthStopped = {
                                DispatchQueue.main.async {
                                    print("✅ Session complete — normal app")
                                    self.blurScreen(false)
                                    // Show your main app UI here
                                    // Don't lock — session just expired naturally
                                }
                            }

                        }
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
                    case .deniedTampered:
                        self.previewView.showMessage("❌ Security violation detected")
                    }
                }
            }
        }
    }
}

