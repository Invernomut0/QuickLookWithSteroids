import Foundation

/// Validates and caches an OmniPreview Pro license against the Gumroad API.
///
/// License state is persisted in two complementary stores:
///  1. **UserDefaults** (suite = app bundle ID) — fast lookup inside the host app.
///  2. **Signed token file** (`LicenseTokenStore`) — shared path readable by
///     Quick Look extension processes that run in separate sandbox containers.
///
/// The token file approach solves the sandbox container isolation problem without
/// requiring an App Group entitlement (which needs a real Apple Developer certificate).
public final class LicenseManager: @unchecked Sendable {

    public static let shared = LicenseManager()

    // MARK: Constants

    static let productPermalink = "lghiqc"
    static let productID = "PrbYxrki-uQ8KxwsawhkDQ=="
    // Using the containing app's bundle ID as suite name allows both the
    // host app and Quick Look extensions to share the same UserDefaults.
    static let defaultsSuite    = "com.omnipreview.OmniPreview"
    static let cacheValidity: TimeInterval = 7  * 24 * 3600   // 7 days
    static let gracePeriod:   TimeInterval = 30 * 24 * 3600   // 30 days

    // MARK: Storage

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.defaultsSuite) ?? .standard
        migrateTokenFileIfNeeded()
    }

    /// If the host app has a valid license in UserDefaults but the token file
    /// is missing (e.g. first launch after upgrading to token-based sharing),
    /// write the token immediately so Quick Look extensions see Pro status.
    private func migrateTokenFileIfNeeded() {
        guard
            defaults.bool(forKey: "isValid"),
            let lastValidated = defaults.object(forKey: "lastValidated") as? Date,
            Date().timeIntervalSince(lastValidated) < Self.gracePeriod,
            let key = defaults.string(forKey: "licenseKey"),
            !LicenseTokenStore.isValid()
        else { return }
        LicenseTokenStore.write(licenseKey: key)
    }

    // MARK: Public API

    public var licenseKey: String? {
        defaults.string(forKey: "licenseKey")
    }

    /// Synchronous read — suitable for use from Quick Look extension processes.
    ///
    /// Checks two sources (either is sufficient to unlock Pro):
    ///  1. **UserDefaults** — works inside the host app container.
    ///  2. **Signed token file** — shared path readable by extension sandbox containers.
    public var isProUnlocked: Bool {
        // Fast path: token file works in both the app and extension contexts.
        if LicenseTokenStore.isValid() { return true }

        // Fallback: UserDefaults (only readable inside the host app container).
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
            // Write signed token file so the QL extension can read Pro status.
            LicenseTokenStore.write(licenseKey: key)
        }
        return valid
    }

    public func deactivate() {
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "isValid")
        defaults.removeObject(forKey: "lastValidated")
        defaults.synchronize()
        // Remove the token file so the extension also drops back to Free.
        LicenseTokenStore.delete()
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
            if valid {
                // Refresh the signed token file so the extension keeps Pro access.
                LicenseTokenStore.write(licenseKey: key)
            } else {
                LicenseTokenStore.delete()
            }
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
