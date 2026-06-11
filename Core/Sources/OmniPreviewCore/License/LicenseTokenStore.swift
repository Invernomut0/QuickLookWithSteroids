import Foundation
import CryptoKit

/// Writes and reads a signed license token to a shared path on disk.
///
/// Both the host app and the Quick Look extension processes read from the same
/// real-home path (`~/Library/Application Support/OmniPreview/license.token`)
/// even when sandboxed. The extension entitlements include a
/// `temporary-exception.files.home-relative-path.read-only` for that directory.
///
/// Security model: the token is HMAC-SHA256 signed. Any modification to the
/// license key or expiry date will break the signature and the token is rejected.
/// The HMAC secret is split to make static binary analysis marginally harder.
public enum LicenseTokenStore {

    // MARK: - Path

    static var tokenURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OmniPreview/license.token")
    }

    // MARK: - Public API

    /// Write a valid signed token for `licenseKey`.
    /// - Parameter licenseKey: The Gumroad license key that was just validated.
    /// - Parameter graceDays: Token lifetime in days (default: 30, matching gracePeriod).
    public static func write(licenseKey: String, graceDays: Int = 30) {
        let expiry = Date().addingTimeInterval(Double(graceDays) * 86_400)
        let sig = hmac(for: licenseKey, expiry: expiry)
        let token: [String: Any] = [
            "k": licenseKey,
            "e": expiry.timeIntervalSince1970,
            "h": sig
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: token, options: []) else {
            return
        }
        let dir = tokenURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            try data.write(to: tokenURL, options: .atomic)
        } catch {
            // Write failures are non-fatal; the app still stores the key in UserDefaults.
        }
    }

    /// Returns `true` when a valid, unexpired, untampered token exists on disk.
    /// Safe to call from sandboxed Quick Look extension processes.
    public static func isValid() -> Bool {
        guard
            let data  = try? Data(contentsOf: tokenURL),
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let key   = json["k"] as? String,
            let expiryTs = json["e"] as? TimeInterval,
            let sig   = json["h"] as? String
        else { return false }

        let expiry = Date(timeIntervalSince1970: expiryTs)
        guard expiry > Date() else { return false }

        let expected = hmac(for: key, expiry: expiry)
        return sig == expected
    }

    /// Delete the token (called on license deactivation).
    public static func delete() {
        try? FileManager.default.removeItem(at: tokenURL)
    }

    // MARK: - HMAC

    private static func hmac(for key: String, expiry: Date) -> String {
        // Secret split across constants to raise the cost of static binary analysis.
        let p1 = "omni"; let p2 = "prev-ql"; let p3 = "-tok26"
        let secret = SymmetricKey(data: Data((p1 + p2 + p3).utf8))
        let message = "\(key)|\(expiry.timeIntervalSince1970)"
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secret)
        return Data(code).base64EncodedString()
    }
}
