import Foundation
import os
import Security

public protocol PairingStore: Sendable {
    func loadPairings() throws -> [PairingRecord]
    func savePairing(_ record: PairingRecord) throws
    func deletePairing(peerID: UUID) throws
    func localDeviceID() throws -> UUID
}

public enum PairingStoreError: Error, Equatable {
    case keychain(OSStatus)
}

// @unchecked: every access to the mutable state goes through `lock`.
public final class InMemoryPairingStore: PairingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UUID: PairingRecord] = [:]
    private var deviceID: UUID?

    public init(deviceID: UUID? = nil) {
        self.deviceID = deviceID
    }

    public func loadPairings() throws -> [PairingRecord] {
        lock.withLock { Array(records.values) }
    }

    public func savePairing(_ record: PairingRecord) throws {
        lock.withLock { records[record.peerID] = record }
    }

    public func deletePairing(peerID: UUID) throws {
        lock.withLock { records[peerID] = nil }
    }

    public func localDeviceID() throws -> UUID {
        lock.withLock {
            if let deviceID { return deviceID }
            let fresh = UUID()
            deviceID = fresh
            return fresh
        }
    }
}

// The install id lives beside the pairings, with the same this-device-only class, so
// the two survive or vanish together (open question 10).
public struct KeychainPairingStore: PairingStore {
    enum Kind: String {
        case pairing = "pairings"
        case device
    }

    static let deviceAccount = "local-device"

    public let service: String
    public let useDataProtectionKeychain: Bool

    #if os(macOS)
        public static let defaultUsesDataProtectionKeychain = false
    #else
        public static let defaultUsesDataProtectionKeychain = true
    #endif

    private let log = Logger(subsystem: "co.sharepad.wire", category: "pairing-store")

    public init(
        service: String = "co.sharepad.wire",
        useDataProtectionKeychain: Bool = Self.defaultUsesDataProtectionKeychain
    ) {
        self.service = service
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func loadPairings() throws -> [PairingRecord] {
        try accounts(kind: .pairing).compactMap { account in
            guard let data = try read(kind: .pairing, account: account) else { return nil }
            do {
                return try PairingRecord.decode(data)
            } catch {
                log.error("skipping an unreadable pairing record")
                return nil
            }
        }
    }

    public func savePairing(_ record: PairingRecord) throws {
        try write(record.encoded(), kind: .pairing, account: record.peerID.uuidString)
    }

    public func deletePairing(peerID: UUID) throws {
        var query = baseQuery(kind: .pairing)
        query[kSecAttrAccount as String] = peerID.uuidString
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PairingStoreError.keychain(status)
        }
    }

    public func localDeviceID() throws -> UUID {
        if let existing = try storedDeviceID() { return existing }
        let fresh = UUID()
        var query = baseQuery(kind: .device)
        query[kSecAttrAccount as String] = Self.deviceAccount
        query[kSecValueData as String] = Data(fresh.uuidString.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return fresh
        case errSecDuplicateItem:
            guard let raced = try storedDeviceID() else { throw PairingStoreError.keychain(status) }
            return raced
        default:
            throw PairingStoreError.keychain(status)
        }
    }

    func removeAll() throws {
        for kind in [Kind.pairing, .device] {
            for _ in 0 ..< 1000 {
                let status = SecItemDelete(baseQuery(kind: kind) as CFDictionary)
                if status == errSecItemNotFound { break }
                guard status == errSecSuccess else { throw PairingStoreError.keychain(status) }
            }
        }
    }

    func baseQuery(kind: Kind) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).\(kind.rawValue)",
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func storedDeviceID() throws -> UUID? {
        guard let data = try read(kind: .device, account: Self.deviceAccount) else { return nil }
        return String(data: data, encoding: .utf8).flatMap(UUID.init(uuidString:))
    }

    // The file-based macOS keychain cannot return data for more than one item per
    // query (errSecParam), so list accounts first and read each one.
    private func accounts(kind: Kind) throws -> [String] {
        var query = baseQuery(kind: kind)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        default:
            throw PairingStoreError.keychain(status)
        }
    }

    private func read(kind: Kind, account: String) throws -> Data? {
        var query = baseQuery(kind: kind)
        query[kSecAttrAccount as String] = account
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw PairingStoreError.keychain(status)
        }
    }

    private func write(_ data: Data, kind: Kind, account: String) throws {
        var query = baseQuery(kind: kind)
        query[kSecAttrAccount as String] = account
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw PairingStoreError.keychain(added) }
        } else if status != errSecSuccess {
            throw PairingStoreError.keychain(status)
        }
    }
}
