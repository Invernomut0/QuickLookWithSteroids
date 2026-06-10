import Foundation

/// Per-renderer enable/disable flags. Unset means enabled.
///
/// Note: extension processes have their own defaults domain; sharing these
/// flags with the Quick Look extensions requires an App Group, which needs
/// real (team-based) code signing — see ROADMAP.
public enum RendererSettings {
    public static var defaults: UserDefaults = .standard

    static func key(_ id: String) -> String { "renderer.\(id).enabled" }

    public static func isEnabled(id: String) -> Bool {
        defaults.object(forKey: key(id)) as? Bool ?? true
    }

    public static func setEnabled(id: String, _ enabled: Bool) {
        defaults.set(enabled, forKey: key(id))
    }
}
