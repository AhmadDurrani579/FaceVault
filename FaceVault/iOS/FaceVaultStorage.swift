//
//  FaceVaultStorage.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import Foundation
import Security
import CryptoKit

public class FaceVaultStorage {
    
    private let keyTag = "com.facevault.embeddingkey"
    private let embeddingKey = "com.facevault.embedding"
    
    public init() {}
    
    // MARK: - Save Embedding
    public func saveEmbedding(_ embedding: [Float]) -> Bool {
        guard let key = getOrCreateKey() else {
            print("❌ FaceVault: Could not get Secure Enclave key")
            return false
        }
        
        do {
            // Convert [Float] → Data
            let data = floatsToData(embedding)
            
            // Encrypt with Secure Enclave public key
            let encrypted = try encrypt(data: data, key: key)
            
            // Save to Keychain
            return saveToKeychain(data: encrypted, account: embeddingKey)

        } catch {
            print("❌ FaceVault: Encryption failed — \(error)")
            return false
        }
    }
    
    // MARK: - Load Embedding
    public func loadEmbedding() -> [Float]? {
        guard let key = getOrCreateKey(),
              let encrypted = loadFromKeychain(account: embeddingKey) else {
            print("❌ FaceVault: Could not load embedding")
            return nil
        }
        
        do {
            let data = try decrypt(data: encrypted, key: key)
            return dataToFloats(data)
        } catch {
            print("❌ FaceVault: Decryption failed — \(error)")
            return nil
        }
    }
    
    // MARK: - Delete Embedding
    public func deleteEmbedding() -> Bool {
        return deleteFromKeychain(account: embeddingKey)
    }
    
    public func hasEnrolledFace() -> Bool {
        return loadFromKeychain(account: embeddingKey) != nil
    }

    
    // MARK: - Secure Enclave Key
    private func getOrCreateKey() -> SecKey? {
        // Try load existing key
        if let key = loadKey() { return key }
        // Create new key
        return createKey()
    }
    
    private func createKey() -> SecKey? {
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryAny],
            nil
        ) else { return nil }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:      256,
            kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String:  access
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("❌ FaceVault: Key creation failed — \(error!.takeRetainedValue())")
            return nil
        }
        
        return key
    }
    
    private func loadKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String:                  kSecClassKey,
            kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String:     keyTag.data(using: .utf8)!,
            kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String:              true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return (item as! SecKey)
    }
    
    // MARK: - Encrypt / Decrypt
    private func encrypt(data: Data, key: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            throw FaceVaultStorageError.keyError
        }
        
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            throw FaceVaultStorageError.encryptionFailed
        }
        
        return encrypted as Data
    }
    
    private func decrypt(data: Data, key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(
            key,
            .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            throw FaceVaultStorageError.decryptionFailed
        }
        
        return decrypted as Data
    }
    
    // MARK: - Keychain
    private func saveToKeychain(data: Data, account: String) -> Bool {
        _ = deleteFromKeychain(account: account)
        
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      account,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:        data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        let success = status == errSecSuccess
        print(success ? "✅ FaceVault: Saved to Keychain [\(account)]" : "❌ FaceVault: Keychain save failed \(status)")
        return success
    }
    
    public func clearOnFreshInstall() {
        let key = "FaceVault_FirstLaunch"
        if UserDefaults.standard.bool(forKey: key) == false {
            _ = deleteEmbedding()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
    
    private func deleteFromKeychain(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    public func deletePointCloud() -> Bool {
        return deleteFromKeychain(account: "com.facevault.pointcloud")
    }

    // MARK: - Save Point Cloud
    public func savePointCloud(_ points: [SIMD3<Float>]) -> Bool {
        guard let key = getOrCreateKey() else { return false }
        
        do {
            let data = pointsToData(points)
            let encrypted = try encrypt(data: data, key: key)
            return saveToKeychain(data: encrypted, account: "com.facevault.pointcloud")
        } catch {
            print("❌ FaceVault: Point cloud encryption failed — \(error)")
            return false
        }
    }

    // MARK: - Load Point Cloud
    public func loadPointCloud() -> [SIMD3<Float>]? {
        guard let key = getOrCreateKey(),
              let encrypted = loadFromKeychain(account: "com.facevault.pointcloud") else {
            return nil
        }
        
        do {
            let data = try decrypt(data: encrypted, key: key)
            return dataToPoints(data)
        } catch {
            print("❌ FaceVault: Point cloud decryption failed — \(error)")
            return nil
        }
    }

    private func pointsToData(_ points: [SIMD3<Float>]) -> Data {
        var copy = points
        return Data(bytes: &copy, count: copy.count * MemoryLayout<SIMD3<Float>>.stride)
    }

    private func dataToPoints(_ data: Data) -> [SIMD3<Float>] {
        let count = data.count / MemoryLayout<SIMD3<Float>>.stride
        return data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: SIMD3<Float>.self).prefix(count))
        }
    }


    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    
    // MARK: - Float Conversion
    private func floatsToData(_ floats: [Float]) -> Data {
        var copy = floats
        return Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
    }
    
    private func dataToFloats(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
    }
}

// MARK: - Errors
enum FaceVaultStorageError: Error {
    case keyError
    case encryptionFailed
    case decryptionFailed
}
