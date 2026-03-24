//
//  ViewController.swift
//  FaceVaultDemo
//
//  Created by Ahmad on 24/03/2026.
//

import UIKit
import FaceVault

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        testMatcher()
        // Do any additional setup after loading the view.
    }
    
    func testMatcher() {
        let sdk = FaceVaultSDK()
        
        // Fake identical 128-dim vectors
        let vec = (0..<128).map { _ in Float.random(in: 0...1) }
        
        let score = sdk.similarity(vec, vec)
        let matched = sdk.isMatch(vec, vec)
        
        print("✅ Score: \(score)")
        print("✅ Match: \(matched)")
    }

}

