import Foundation
import Observation
import Supabase

struct SupabaseConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    static func loadFromBundle() -> SupabaseConfiguration? {
        guard
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let rawKey = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
        else {
            return nil
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            trimmedURL.hasPrefix("https://"),
            trimmedURL.contains(".supabase.co"),
            trimmedKey.hasPrefix("sb_publishable_") || trimmedKey.split(separator: ".").count == 3,
            trimmedURL.contains("$(") == false,
            trimmedKey.contains("$(") == false,
            let url = URL(string: trimmedURL)
        else {
            return nil
        }

        return SupabaseConfiguration(url: url, publishableKey: trimmedKey)
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
            return "同期中"
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
        configureFromBundle()
    }

    func configureFromBundle() {
        guard let configuration = SupabaseConfiguration.loadFromBundle() else {
            status = .unconfigured
            self.configuration = nil
            client = nil
            return
        }

        self.configuration = configuration
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        status = .signedOut
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
