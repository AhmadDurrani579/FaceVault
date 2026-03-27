//
//  FaceVaultLogger.swift
//  FaceVault
//
//  Created by Ahmad on 27/03/2026.
//


import Foundation

public enum FaceVaultLogLevel {
    case info
    case warning
    case error
}

public class FaceVaultLogger {
    
    public static var isEnabled: Bool = false // off by default
    
    static func log(_ message: String,
                    level: FaceVaultLogLevel = .info,
                    file: String = #file,
                    line: Int = #line) {
        
        guard isEnabled else { return }
        
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let prefix: String
        
        switch level {
        case .info:    prefix = "[FaceVault]"
        case .warning: prefix = "[FaceVault ⚠️]"
        case .error:   prefix = "[FaceVault ❌]"
        }
        
        print("\(prefix) \(message) (\(filename):\(line))")
    }
}
