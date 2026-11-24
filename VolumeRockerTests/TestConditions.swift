import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// For tests that click inside real windows. They need a logged-in screen session, which CI machines
    /// don't have (there, a synthesized click can wait forever), so CI skips them. They run on developer Macs.
    static var needsInteractiveSession: Self {
        .disabled(
            if: ProcessInfo.processInfo.environment["CI"] != nil,
            "Needs a logged-in screen session; skipped on CI"
        )
    }
}
