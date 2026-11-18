import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Whether the window showing this view is actually visible on screen. The menu bar panel stays alive while
    /// closed, and SwiftUI keeps its animations running, so live views (meters) use this to pause themselves.
    @Entry var isWindowVisible = true
}

extension View {
    /// Tracks whether this view's window is visible and publishes it as `\.isWindowVisible` to its content.
    func trackingWindowVisibility() -> some View {
        modifier(WindowVisibilityModifier())
    }
}

private struct WindowVisibilityModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.isWindowVisible, isVisible)
            .background(WindowVisibilityReader { isVisible = $0 })
    }
}

/// An invisible AppKit view that reports its window's occlusion (visibility) state.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context _: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context _: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Selector-based observers are removed automatically when the view is deallocated.
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionDidChange),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
            report()
        }

        @objc private func occlusionDidChange(_: Notification) {
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
