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
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreview()
        previewView.showMessage(" Initializing...")
        
        sdk.prepare {
            if self.sdk.isEnrolled() {
                self.startAuthentication()
            } else {
                self.startEnrollment()
            }
        }
    }
    
    // MARK: - Setup
    private func setupPreview() {
        previewView.frame = view.bounds
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewView)
        sdk.attachPreview(previewView)
    }
    
    // MARK: - Enrollment
    private func startEnrollment() {
        sdk.enroll { success in
            DispatchQueue.main.async {
                if success {
                    self.startAuthentication()
                } else {
                    self.previewView.showMessage(" Enrollment failed — try again")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startEnrollment()
                    }
                }
            }
        }
    }
    
    // MARK: - Authentication
    private func startAuthentication() {
        sdk.authenticate { result in
            DispatchQueue.main.async {
                switch result {
                case .authenticated(let confidence):
                    self.onAuthenticated(confidence: confidence)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.sdk.estimateAge { result in
                            if let result = result {
                                print(" Age: \(result.estimatedAge)")
                                print(" Range: \(result.ageRange)")
                                print(" IsAdult: \(result.isAdult)")
                            } else {
                                print(" Age estimation failed — no pixel buffer")
                            }
                        }
                    }

                    
                case .deniedNoMatch:
                    self.previewView.showMessage(" Face does not match")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startAuthentication()
                    }
                    
                case .deniedLiveness:
                    self.previewView.showMessage(" Liveness check failed")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startAuthentication()
                    }
                    
                case .deniedMultipleFaces:
                    self.previewView.showMessage(" Multiple faces detected")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startAuthentication()
                    }
                case .deniedInsufficientData:
                    self.startEnrollment()
                    
                case .requiresRetry:
                    self.startAuthentication()
                    
                case .deniedTampered:
                    self.previewView.showMessage(" Security violation detected")
                }
            }
        }
    }
    
    // MARK: - Post Authentication
    private func onAuthenticated(confidence: Float) {
        previewView.showMessage(" Authenticated!")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.previewView.isHidden = true
            self.setupLogoutButton()
            self.startContinuousAuth()
        }
    }
    
    private func startContinuousAuth() {
        sdk.onContinuousAuthStopped = {
            DispatchQueue.main.async {
                self.blurScreen(false)
            }
        }
        
        sdk.startContinuousAuth(interval: 1.0, maxDuration: 120.0) { event in
            switch event {
            case .faceVerified:  self.blurScreen(false)
            case .faceLost:      self.blurScreen(true)
            case .faceChanged:   self.lockApp()
            case .multipleFaces: self.blurScreen(true)
            }
        }
    }
    
    // MARK: - UI Helpers
    private func blurScreen(_ blur: Bool) {
        DispatchQueue.main.async {
            if blur {
                guard self.view.viewWithTag(999) == nil else { return }
                let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
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
        sdk.stopContinuousAuth()
        blurScreen(false)
        previewView.isHidden = false
        previewView.showMessage(" Session expired")
    }
    
    // MARK: - Logout
    private func setupLogoutButton() {
        guard view.viewWithTag(998) == nil else { return }
        let btn = UIButton(type: .system)
        btn.setTitle("Logout", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.red.withAlphaComponent(0.7)
        btn.layer.cornerRadius = 10
        btn.frame = CGRect(x: 20, y: 60, width: 80, height: 36)
        btn.tag = 998
        btn.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        view.addSubview(btn)
    }
    
    @objc private func logoutTapped() {
        view.viewWithTag(998)?.removeFromSuperview()
        sdk.logout()
        previewView.isHidden = false
        previewView.resetProgress()
        startEnrollment()
    }
}
