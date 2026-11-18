import CoreAudio
import Foundation

/// Watches one Core Audio property and calls `handler` on the main actor whenever it changes.
/// The listener is removed automatically when this object is released.
final class PropertyListener {
    private let objectID: AudioObjectID
    private let address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    @MainActor
    init?(objectID: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping @MainActor @Sendable () -> Void) {
        self.objectID = objectID
        self.address = address
        // Core Audio calls the block on the queue we pass (main), so it is safe to assume main-actor isolation.
        block = { _, _ in MainActor.assumeIsolated { handler() } }
        var address = address
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block) == noErr else { return nil }
    }

    deinit {
        var address = address
        AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
    }
}
