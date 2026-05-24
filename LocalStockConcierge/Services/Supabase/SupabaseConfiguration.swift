import Foundation
import Observation
import Supabase

struct SupabaseConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    private static let storedURLKey = "localstock.supabase.url"
    private static let storedPublishableKey = "localstock.supabase.publishableKey"

    var projectHost: String {
        url.host ?? url.absoluteString
    }

    var keyPreview: String {
        guard publishableKey.count > 18 else { return "保存済み" }
        return "\(publishableKey.prefix(14))...\(publishableKey.suffix(4))"
    }

    static var hasStoredConfiguration: Bool {
        UserDefaults.standard.string(forKey: storedURLKey) != nil
            || UserDefaults.standard.string(forKey: storedPublishableKey) != nil
    }

    static func load() -> SupabaseConfiguration? {
        loadFromDevice() ?? loadFromBundle()
    }

    static func loadStoredValues() -> (url: String, key: String)? {
        guard
            let rawURL = UserDefaults.standard.string(forKey: storedURLKey),
            let rawKey = UserDefaults.standard.string(forKey: storedPublishableKey)
        else {
            return nil
        }

        return (rawURL, rawKey)
    }

    static func saveToDevice(urlString: String, publishableKey: String) throws -> SupabaseConfiguration {
        let configuration = try validate(urlString: urlString, publishableKey: publishableKey)
        UserDefaults.standard.set(configuration.url.absoluteString, forKey: storedURLKey)
        UserDefaults.standard.set(configuration.publishableKey, forKey: storedPublishableKey)
        return configuration
    }

    static func clearStored() {
        UserDefaults.standard.removeObject(forKey: storedURLKey)
        UserDefaults.standard.removeObject(forKey: storedPublishableKey)
    }

    private static func loadFromDevice() -> SupabaseConfiguration? {
        guard let values = loadStoredValues() else { return nil }
        return try? validate(urlString: values.url, publishableKey: values.key)
    }

    static func loadFromBundle() -> SupabaseConfiguration? {
        guard
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let rawKey = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
        else {
            return nil
        }

        return try? validate(urlString: rawURL, publishableKey: rawKey)
    }

    static func validate(urlString rawURL: String, publishableKey rawKey: String) throws -> SupabaseConfiguration {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            trimmedURL.contains("$(") == false,
            trimmedKey.contains("$(") == false,
            trimmedURL.isEmpty == false,
            trimmedKey.isEmpty == false
        else {
            throw SupabaseConfigurationError.placeholderOrEmpty
        }

        guard
            let url = URL(string: trimmedURL),
            url.scheme == "https",
            url.host?.hasSuffix(".supabase.co") == true
        else {
            throw SupabaseConfigurationError.invalidURL
        }

        let lowerKey = trimmedKey.lowercased()
        guard
            lowerKey.contains("sb_secret_") == false,
            lowerKey.contains("service_role") == false
        else {
            throw SupabaseConfigurationError.secretKeyNotAllowed
        }

        if trimmedKey.hasPrefix("sb_publishable_") == false {
            guard trimmedKey.split(separator: ".").count == 3 else {
                throw SupabaseConfigurationError.invalidPublishableKey
            }

            guard jwtRole(in: trimmedKey) == "anon" else {
                throw SupabaseConfigurationError.secretKeyNotAllowed
            }
        }

        return SupabaseConfiguration(url: url, publishableKey: trimmedKey)
    }

    private static func jwtRole(in key: String) -> String? {
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload.append(String(repeating: "=", count: 4 - padding))
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["role"] as? String
    }
}

enum SupabaseConfigurationError: LocalizedError {
    case placeholderOrEmpty
    case invalidURL
    case invalidPublishableKey
    case secretKeyNotAllowed

    var errorDescription: String? {
        switch self {
        case .placeholderOrEmpty:
            return "Supabase URL と publishable key を入力してください。"
        case .invalidURL:
            return "Supabase URL は https://PROJECT_REF.supabase.co の形式で入力してください。"
        case .invalidPublishableKey:
            return "publishable key または legacy anon key を入力してください。"
        case .secretKeyNotAllowed:
            return "service_role / secret key はiOSアプリに保存できません。publishable keyを使ってください。"
        }
    }
}

enum CloudAuthStatus: Equatable {
    case unconfigured
    case signedOut
    case signingIn
    case signedIn(userID: UUID, email: String?)
    case failed(String)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unconfigured:
            return "未設定"
        case .signedOut:
            return "未ログイン"
        case .signingIn:
            return "確認中"
        case .signedIn:
            return "接続済み"
        case .failed(_):
            return "エラー"
        }
    }
}

@MainActor
@Observable
final class SupabaseAuthController {
    private(set) var status: CloudAuthStatus = .unconfigured
    private(set) var configuration: SupabaseConfiguration?
    private(set) var client: SupabaseClient?
    var lastMessage: String?

    init() {
        configure()
    }

    func configure() {
        guard let configuration = SupabaseConfiguration.load() else {
            status = .unconfigured
            self.configuration = nil
            client = nil
            return
        }

        apply(configuration)
        status = .signedOut
    }

    func configureFromBundle() {
        configure()
    }

    func saveConfiguration(urlString: String, publishableKey: String) throws {
        let configuration = try SupabaseConfiguration.saveToDevice(urlString: urlString, publishableKey: publishableKey)
        apply(configuration)
        status = .signedOut
        lastMessage = "Supabase接続を保存しました。メールリンクでログインしてください。"
    }

    func clearStoredConfiguration() {
        SupabaseConfiguration.clearStored()
        configure()
        lastMessage = "端末内のSupabase接続設定を削除しました。"
    }

    var projectHost: String? {
        configuration?.projectHost
    }

    var keyPreview: String? {
        configuration?.keyPreview
    }

    var hasStoredConfiguration: Bool {
        SupabaseConfiguration.hasStoredConfiguration
    }

    private func apply(_ configuration: SupabaseConfiguration) {
        self.configuration = configuration
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    func refreshSession() async {
        guard let client else {
            status = .unconfigured
            return
        }

        do {
            let session = try await client.auth.session
            status = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            if case .unconfigured = status {
                return
            }
            status = .signedOut
        }
    }

    func sendMagicLink(email: String) async throws {
        guard let client else { throw SupabaseAuthError.unconfigured }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { throw SupabaseAuthError.invalidEmail }

        status = .signingIn
        try await client.auth.signInWithOTP(
            email: trimmed,
            redirectTo: URL(string: "localstock://login-callback")!
        )
        lastMessage = "メールのリンクを開くと、このiPhoneで同期が始まります。"
        status = .signedOut
    }

    func handleOpenURL(_ url: URL) async throws {
        guard let client else { throw SupabaseAuthError.unconfigured }
        try await client.auth.session(from: url)
        await refreshSession()
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            status = .signedOut
            lastMessage = "ログアウトしました。端末内キャッシュは残ります。"
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

enum SupabaseAuthError: LocalizedError {
    case unconfigured
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .unconfigured:
            return "Supabase URL と publishable key が未設定です。"
        case .invalidEmail:
            return "メールアドレスを確認してください。"
        }
    }
}
