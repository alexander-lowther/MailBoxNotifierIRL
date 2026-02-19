//
//  DeviceIdentity.swift
//  Mail Box Notifer
//
//  Created by user281046 on 2/2/26.
//
/*
import UIKit

enum DeviceIdentity {
    private static let key = "stable_device_id"

    static func id() -> String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}

*/
import Foundation
import Security

enum DeviceIdentity {
    private static let service = "com.mailboxnotifierirl.deviceidentity"
    private static let account = "stable_device_id"
    private static let lock = NSLock()

    static func id() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = readKeychainString(service: service, account: account),
           !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString.lowercased()
        _ = writeKeychainString(newID, service: service, account: account)
        return newID
    }

    /// Manual escape hatch if you ever want to force a new identity.
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        deleteKeychainItem(service: service, account: account)
    }

    // MARK: - Keychain helpers (minimal)

    private static func readKeychainString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }

        return str
    }

    @discardableResult
    private static func writeKeychainString(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)

        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // Else add
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
