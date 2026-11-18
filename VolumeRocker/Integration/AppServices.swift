import Foundation

/// The running app's shared objects, for code that SwiftUI doesn't hand them to directly
/// (App Intents run by Shortcuts and Siri). Set once at launch by the app delegate.
@MainActor
enum AppServices {
    static var model: MixerModel?
}

/// Thrown by App Intents when the app isn't ready to act.
enum AppServicesError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        "Volume Rocker isn’t ready yet. Try again in a moment."
    }
}
