import AppKit
import Darwin

/// The user-facing app a process belongs to.
struct ResolvedApp: Equatable {
    /// Stable identifier, normally the app's bundle ID. Used as the key for saved settings.
    let id: String
    let name: String
    let bundlePath: String?
    /// True for apps that show in the Dock (as opposed to background agents and daemons).
    let isRegularApp: Bool
}

/// Maps process IDs to the app the user thinks of, so helper processes are grouped under their parent.
///
/// For example, "Google Chrome Helper (Renderer)" lives inside Google Chrome.app, and Safari's sound is played
/// by WebKit's "GPU process", for which macOS records Safari as the *responsible* process.
@MainActor
final class AppResolver {
    private var cache: [pid_t: ResolvedApp] = [:]

    func resolve(pid: pid_t, bundleID: String?) -> ResolvedApp {
        if let cached = cache[pid] {
            return cached
        }
        let app = Self.computeApp(pid: pid, bundleID: bundleID)
        cache[pid] = app
        return app
    }

    /// Forgets processes that no longer exist (process IDs can be reused).
    func prune(keeping pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private static func computeApp(pid: pid_t, bundleID: String?) -> ResolvedApp {
        var candidates = [pid]
        if let responsible = responsiblePID(for: pid), responsible != pid, responsible > 1 {
            candidates.insert(responsible, at: 0)
        }

        for candidate in candidates {
            if let path = executablePath(of: candidate),
               let appPath = outermostAppBundlePath(in: path),
               let bundle = Bundle(path: appPath),
               let identifier = bundle.bundleIdentifier {
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
                return ResolvedApp(
                    id: identifier,
                    name: running?.localizedName ?? displayName(ofAppAt: appPath),
                    bundlePath: appPath,
                    isRegularApp: running?.activationPolicy == .regular
                )
            }
        }

        if let running = NSRunningApplication(processIdentifier: pid) {
            return ResolvedApp(
                id: running.bundleIdentifier ?? bundleID ?? "pid.\(pid)",
                name: running.localizedName ?? bundleID ?? "Process \(pid)",
                bundlePath: running.bundleURL?.path,
                isRegularApp: running.activationPolicy == .regular
            )
        }

        let fallbackName = executablePath(of: pid).map { URL(fileURLWithPath: $0).lastPathComponent }
        return ResolvedApp(
            id: bundleID ?? "pid.\(pid)",
            name: fallbackName ?? bundleID ?? "Process \(pid)",
            bundlePath: nil,
            isRegularApp: false
        )
    }

    /// The outermost `.app` bundle in a path, e.g.
    /// `/Applications/Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app/…` → `/Applications/Google Chrome.app`.
    nonisolated static func outermostAppBundlePath(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let prefix = components[...index].joined(separator: "/")
        return prefix.isEmpty ? nil : prefix
    }

    private static func displayName(ofAppAt path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// macOS tracks which app is "responsible" for each helper process. The lookup function is not public API,
    /// so it is loaded dynamically; if it is ever missing we fall back to the bundle-path method above.
    private static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: ResponsibleFunction.self)
        let result = function(pid)
        return result > 0 ? result : nil
    }

    static func icon(for app: ResolvedApp) -> NSImage {
        if let path = app.bundlePath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
