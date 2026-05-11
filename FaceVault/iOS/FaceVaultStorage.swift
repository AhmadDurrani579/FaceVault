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
    
    private let keyTag    = "com.facevault.embeddingkey"
    private let embeddingKey = "com.facevault.embedding"
    private let pointCloudKey = "com.facevault.pointcloud"
    
    public init() {}
    
    // MARK: - Save Embedding
    public func saveEmbedding(_ embedding: [Float]) -> Bool {
        guard let key = getOrCreateKey() else {
            FaceVaultLogger.log("Could not get Secure Enclave key", level: .error)
            return false
        }
        do {
            let encrypted = try encrypt(data: floatsToData(embedding), key: key)
            return saveToKeychain(data: encrypted, account: embeddingKey)
        } catch {
            FaceVaultLogger.log("Encryption failed — \(error)", level: .error)
            return false
        }
    }
    
    // MARK: - Load Embedding
    public func loadEmbedding() -> [Float]? {
        guard let key = getOrCreateKey(),
              let encrypted = loadFromKeychain(account: embeddingKey) else {
            return nil
        }
        do {
            let data = try decrypt(data: encrypted, key: key)
            return dataToFloats(data)
        } catch {
            FaceVaultLogger.log("Decryption failed — \(error)", level: .error)
            return nil
        }
    }
    
    // MARK: - Delete Embedding
    public func deleteEmbedding() -> Bool {
        return deleteFromKeychain(account: embeddingKey)
    }
    
    // MARK: - Enrolled Check
    // Only checks keychain metadata — no biometric, no Secure Enclave access
    public func hasEnrolledFace() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: embeddingKey,
            kSecReturnData as String:  false  // metadata only — no decryption
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }
    
    // MARK: - Point Cloud
    public func savePointCloud(_ points: [SIMD3<Float>]) -> Bool {
        guard let key = getOrCreateKey() else { return false }
        do {
            let encrypted = try encrypt(data: pointsToData(points), key: key)
            return saveToKeychain(data: encrypted, account: pointCloudKey)
        } catch { return false }
    }
    
    public func loadPointCloud() -> [SIMD3<Float>]? {
        guard let key = getOrCreateKey(),
              let encrypted = loadFromKeychain(account: pointCloudKey) else { return nil }
        do {
            let data = try decrypt(data: encrypted, key: key)
            return dataToPoints(data)
        } catch { return nil }
    }
    
    public func deletePointCloud() -> Bool {
        return deleteFromKeychain(account: pointCloudKey)
    }
    
    // MARK: - Fresh Install
    public func clearOnFreshInstall() {
        let key = "FaceVault_FirstLaunch"
        if UserDefaults.standard.bool(forKey: key) == false {
            _ = deleteEmbedding()
            _ = deletePointCloud()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
    
    // MARK: - Secure Enclave Key
    // No biometryAny — FaceVault's own liveness is the biometric gate
    private func getOrCreateKey() -> SecKey? {
        if let key = loadKey() { return key }
        return createKey()
    }
    
    private func createKey() -> SecKey? {
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,  // ← no .biometryAny — no Face ID prompt
            nil
        ) else { return nil }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:  256,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String:  access
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(
            attributes as CFDictionary, &error
        ) else {
            FaceVaultLogger.log("Key creation failed — \(error!.takeRetainedValue())",
                                level: .error)
            return nil
        }
        return key
    }
    
    private func loadKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String:          true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
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
        ) else { throw FaceVaultStorageError.encryptionFailed }
        return encrypted as Data
    }
    
    private func decrypt(data: Data, key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(
            key,
            .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
            data as CFData,
            &error
        ) else { throw FaceVaultStorageError.decryptionFailed }
        return decrypted as Data
    }
    
    // MARK: - Keychain
    private func saveToKeychain(data: Data, account: String) -> Bool {
        _ = deleteFromKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:      data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    
    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }
    
    private func deleteFromKeychain(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
    
    // MARK: - Conversions
    private func floatsToData(_ floats: [Float]) -> Data {
        var copy = floats
        return Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
    }
    
    private func dataToFloats(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
    }
    
    private func pointsToData(_ points: [SIMD3<Float>]) -> Data {
        var copy = points
        return Data(bytes: &copy, count: copy.count * MemoryLayout<SIMD3<Float>>.stride)
    }
    
    private func dataToPoints(_ data: Data) -> [SIMD3<Float>] {
        let count = data.count / MemoryLayout<SIMD3<Float>>.stride
        return data.withUnsafeBytes { Array($0.bindMemory(to: SIMD3<Float>.self).prefix(count)) }
    }
}

// MARK: - Errors
enum FaceVaultStorageError: Error {
    case keyError
    case encryptionFailed
    case decryptionFailed
}
