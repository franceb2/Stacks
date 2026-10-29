import Foundation
import Security
import SwiftUI

/// Holds the signed-in server. The server address lives in UserDefaults; the Auth Key lives in the Keychain.
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var client: KavitaClient?

    private let serverKey = "serverURL"
    private let keychainAccount = "kavita-auth-key"

    init() {
        // Preview builds launch the simulator with -demoServer/-demoApiKey; normal use never sets these.
        if let demoServer = UserDefaults.standard.string(forKey: "demoServer"),
           let demoKey = UserDefaults.standard.string(forKey: "demoApiKey"),
           let url = URL(string: demoServer) {
            client = KavitaClient(baseURL: url, apiKey: demoKey)
            return
        }
        if let raw = UserDefaults.standard.string(forKey: serverKey),
           let url = URL(string: raw),
           let key = Keychain.read(account: keychainAccount) {
            client = KavitaClient(baseURL: url, apiKey: key)
        }
    }

    var serverAddress: String { client?.baseURL.absoluteString ?? "" }

    func signIn(server: URL, apiKey: String) async throws {
        let candidate = KavitaClient(baseURL: server, apiKey: apiKey)
        _ = try await candidate.libraries() // proves the key works before saving it
        UserDefaults.standard.set(server.absoluteString, forKey: serverKey)
        Keychain.save(apiKey, account: keychainAccount)
        client = candidate
    }

    func signOut() {
        Keychain.delete(account: keychainAccount)
        client = nil
    }
}

enum Keychain {
    private static let service = "Stacks"

    static func save(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
