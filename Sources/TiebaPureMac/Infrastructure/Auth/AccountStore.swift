import Combine
import Foundation
import Security

protocol AccountStoreService: Sendable {
    func loadData() async throws -> Data?
    func saveData(_ data: Data) async throws
    func clearData() async throws
}

final class AccountStore {
    private let service: AccountStoreService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let operationLock = AccountStoreOperationLock()
    private let accountChanges = PassthroughSubject<Account?, Never>()
    var accountDidChange: AnyPublisher<Account?, Never> { accountChanges.eraseToAnyPublisher() }

    init(service: AccountStoreService) {
        self.service = service
    }

    func load() async throws -> Account? {
        try await withExclusiveOperation {
            try await loadUnlocked()
        }
    }

    private func loadUnlocked() async throws -> Account? {
        guard let data = try await service.loadData() else { return nil }
        do {
            let account = try decoder.decode(Account.self, from: data)
            guard BaiduCredentialPolicy.isValid(account) else {
                throw AccountStoreError.invalidCredentials
            }
            return account
        } catch {
            do {
                try await service.clearData()
            } catch {
                throw AccountStoreError.invalidCredentialCleanupFailed(error as NSError)
            }
            throw error
        }
    }

    func save(_ account: Account) async throws {
        try await withExclusiveOperation {
            try await saveUnlocked(account)
        }
    }

    /// Updates non-secret metadata on the active account without allowing a
    /// stale view to recreate credentials or overwrite refreshed cookies.
    func updateDisplayName(
        _ displayName: String,
        forSession expectedSession: AccountSessionIdentity
    ) async throws {
        try await withExclusiveOperation {
            guard var current = try await loadUnlocked(),
                  current.sessionIdentity == expectedSession else {
                throw AccountStoreError.sessionChanged
            }
            current.displayName = displayName
            try await saveUnlocked(current)
        }
    }

    private func saveUnlocked(_ account: Account) async throws {
        try Task.checkCancellation()
        guard BaiduCredentialPolicy.isValid(account) else {
            throw AccountStoreError.invalidCredentials
        }
        let previousData = try await service.loadData()
        let previousAccount = previousData
            .flatMap { try? decoder.decode(Account.self, from: $0) }
            .flatMap { BaiduCredentialPolicy.isValid($0) ? $0 : nil }
        // Re-encode rather than restore the original bytes so removed legacy
        // fields (including a complete Cookie header) cannot reappear.
        let restorablePreviousData = previousAccount.flatMap { try? encoder.encode($0) }
        let data = try encoder.encode(account)
        try Task.checkCancellation()
        do {
            try await service.saveData(data)
            try Task.checkCancellation()
            try await MainActor.run {
                try Task.checkCancellation()
                accountChanges.send(account)
            }
            // Publishing the account is the commit point. Subscribers are
            // expected to dismiss the login view, which cancels its validation
            // task. Treating that expected dismissal as a failed save would
            // immediately roll the newly stored account back to logged out.
        } catch is CancellationError {
            do {
                if let restorablePreviousData {
                    try await service.saveData(restorablePreviousData)
                } else {
                    try await service.clearData()
                }
            } catch {
                throw AccountStoreError.cancellationRollbackFailed
            }
            await MainActor.run {
                accountChanges.send(previousAccount)
            }
            throw CancellationError()
        }
    }

    func clear() async throws {
        try await withExclusiveOperation {
            try await service.clearData()
            await MainActor.run {
                accountChanges.send(nil)
            }
        }
    }

    private func withExclusiveOperation<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        await operationLock.acquire()
        do {
            let result = try await operation()
            await operationLock.release()
            return result
        } catch {
            await operationLock.release()
            throw error
        }
    }
}

private actor AccountStoreOperationLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if isLocked == false {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

actor MemoryAccountStoreService: AccountStoreService {
    private var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func loadData() async throws -> Data? {
        data
    }

    func saveData(_ data: Data) async throws {
        self.data = data
    }

    func clearData() async throws {
        data = nil
    }
}

protocol KeychainSecurityOperating: Sendable {
    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychainSecurityOperations: KeychainSecurityOperating {
    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

struct KeychainAccountStoreService: AccountStoreService {
    private let service: String
    private let account: String
    private let securityOperations: any KeychainSecurityOperating

    init(
        service: String = "io.github.yamakze.TiebaPureMac.account",
        account: String = "single",
        securityOperations: any KeychainSecurityOperating = SystemKeychainSecurityOperations()
    ) {
        self.service = service
        self.account = account
        self.securityOperations = securityOperations
    }

    func loadData() async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = securityOperations.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { throw KeychainError.invalidItemAttributes }
        return data
    }

    func saveData(_ data: Data) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = securityOperations.update(
            query as CFDictionary,
            attributes: attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = securityOperations.add(addQuery as CFDictionary)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func clearData() async throws {
        try deleteStoredItem()
    }

    private func deleteStoredItem() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = securityOperations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: Error, Equatable {
    case status(OSStatus)
    case invalidItemAttributes
}

enum AccountStoreError: Error, Equatable {
    case cancellationRollbackFailed
    case invalidCredentialCleanupFailed(NSError)
    case invalidCredentials
    case sessionChanged
}
