import Foundation

/// Static facts about the app: name, links and version.
enum AppInfo {
    static let name = "Volume Rocker"
    static let repositoryURL = URL(string: "https://github.com/printMoney/volume-rocker")
    static let issuesURL = URL(string: "https://github.com/printMoney/volume-rocker/issues")
    static let releasesURL = URL(string: "https://github.com/printMoney/volume-rocker/releases")

    /// The running app's version, e.g. "0.1.0 (1)".
    static var versionString: String {
        versionString(from: Bundle.main.infoDictionary ?? [:])
    }

    /// Formats a version string from an Info.plist dictionary. Separated out so it can be unit tested.
    static func versionString(from info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
