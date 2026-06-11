import Foundation

/// Validates and caches an OmniPreview Pro license against the Gumroad API.
///
/// State is stored in a named UserDefaults suite so both the host app and
/// the Quick Look extension processes can read it without App Group signing.
public final class LicenseManager: @unchecked Sendable {

    public static let shared = LicenseManager()

    // MARK: Constants

    static let productPermalink = "lghiqc"
    static let productID = "PrbYxrki-uQ8KxwsawhkDQ=="
    static let defaultsSuite    = "com.omnipreview.license"
    static let cacheValidity: TimeInterval = 7  * 24 * 3600   // 7 days
    static let gracePeriod:   TimeInterval = 30 * 24 * 3600   // 30 days

    // MARK: Storage

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.defaultsSuite) ?? .standard
    }

    // MARK: Public API

    public var licenseKey: String? {
        defaults.string(forKey: "licenseKey")
    }

    /// Synchronous read — suitable for use from Quick Look extension processes.
    /// Returns `true` when a license is stored and within the grace period.
    public var isProUnlocked: Bool {
        guard defaults.bool(forKey: "isValid") else { return false }
        guard let lastValidated = defaults.object(forKey: "lastValidated") as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastValidated) < Self.gracePeriod
    }

    /// Whether the cached validation is still fresh (< 7 days).
    public var isCacheFresh: Bool {
        guard let lastValidated = defaults.object(forKey: "lastValidated") as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastValidated) < Self.cacheValidity
    }

    /// Validates `key` against Gumroad and stores the result.
    /// Throws `LicenseError` on network or API problems.
    @discardableResult
    public func activate(key: String) async throws -> Bool {
        let valid = try await verifyWithGumroad(key: key)
        if valid {
            defaults.set(key, forKey: "licenseKey")
            defaults.set(true, forKey: "isValid")
            defaults.set(Date(), forKey: "lastValidated")
            defaults.synchronize()
        }
        return valid
    }

    public func deactivate() {
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "isValid")
        defaults.removeObject(forKey: "lastValidated")
        defaults.synchronize()
    }

    /// Re-validates in the background; silently updates the cache.
    /// Called on app launch when the cache is stale.
    public func revalidateIfNeeded() {
        guard !isCacheFresh, let key = licenseKey else { return }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard let valid = try? await self.verifyWithGumroad(key: key) else { return }
            self.defaults.set(valid, forKey: "isValid")
            self.defaults.set(Date(), forKey: "lastValidated")
            self.defaults.synchronize()
        }
    }

    // MARK: Gumroad API

    private func verifyWithGumroad(key: String) async throws -> Bool {
        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            throw LicenseError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let safe = { (s: String) -> String in
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        }
        request.httpBody = [
            "product_id=\(safe(Self.productID))",
            "license_key=\(safe(key))",
            "increment_uses_count=false",
        ].joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            print("🔐 License API Response: HTTP \(http.statusCode)")
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("   Response: \(jsonObj)")
            }
            
            if http.statusCode == 404 {
                print("   → License key not found (404)")
                return false
            }
            
            if http.statusCode >= 500 {
                throw LicenseError.serverError(http.statusCode)
            }
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.invalidResponse
        }
        
        let isValid = json["success"] as? Bool ?? false
        print("🔐 License validation result: \(isValid)")
        return isValid
    }
}

// MARK: Errors

public enum LicenseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:        return "License server URL is invalid."
        case .invalidResponse:   return "The license server returned an unexpected response."
        case .serverError(let c): return "License server error (HTTP \(c))."
        }
    }
}
