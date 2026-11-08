import Foundation

/// All user/brew input that eventually becomes a process argument passes here.
/// The rule is intentionally strict: brew tokens never need shell metacharacters.
public enum BrewArgumentValidator {
    public static let maxTokenLength = 128
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@+._/-")

    public static func isValidPackageToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= maxTokenLength else { return false }
        guard !token.hasPrefix("-") else { return false }
        guard !token.contains("..") else { return false }
        guard !token.contains("//"), !token.hasSuffix("/"), !token.hasPrefix("/") else { return false }
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func validatePackageToken(_ token: String) throws -> String {
        guard isValidPackageToken(token) else {
            throw ValidationError.invalidToken(token)
        }
        return token
    }

    /// Search queries are freer than package tokens: multi-word searches need
    /// spaces. But a leading `-` would be parsed by brew as a flag and change
    /// command semantics, and control characters (newlines in particular) have
    /// no legitimate use in a query.
    public static func validateSearchQuery(_ query: String) throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTokenLength else {
            throw ValidationError.invalidToken(query)
        }
        guard !trimmed.hasPrefix("-") else {
            throw ValidationError.invalidToken(query)
        }
        let forbidden = CharacterSet.controlCharacters
        guard trimmed.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw ValidationError.invalidToken(query)
        }
        return trimmed
    }

    public static func isValidPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\u{0000}") else { return false }
        return true
    }

    /// Only http(s) links from brew metadata are opened, and only after this check.
    public static func isSafeWebURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    public enum ValidationError: Error, LocalizedError, Sendable {
        case invalidToken(String)

        public var errorDescription: String? {
            switch self {
            case .invalidToken(let token):
                return "无效的包名：\(token)"
            }
        }
    }
}
