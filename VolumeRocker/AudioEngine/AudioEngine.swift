import CoreAudio
import Foundation
import OSLog

/// What the engine should be doing for one app: tap these processes and play them on this device.
struct TapRequest: Sendable, Equatable {
    let key: String
    let processObjectIDs: [AudioObjectID]
    let outputDeviceID: AudioDeviceID
    let outputDeviceUID: String
    let renderState: TapRenderState
    /// Bumped to force a rebuild with otherwise identical settings, e.g. after wake or a sample-rate change.
    var generation = 0

    static func == (lhs: TapRequest, rhs: TapRequest) -> Bool {
        lhs.key == rhs.key
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.outputDeviceID == rhs.outputDeviceID
            && lhs.outputDeviceUID == rhs.outputDeviceUID
            && lhs.renderState === rhs.renderState
            && lhs.generation == rhs.generation
    }
}

/// Owns every process tap and private aggregate device.
///
/// The engine is declarative: `apply(_:)` receives the complete list of taps that should exist, then starts,
/// restarts or stops sessions to match. Being an actor, the slow Core Audio setup calls never block the UI.
actor AudioEngine {
    static let aggregateUIDPrefix = "io.github.printmoney.VolumeRocker.aggregate."

    private var sessions: [String: TapSession] = [:]
    /// Requests that failed to start, so we don't retry them on every update.
    private var failed: [String: TapRequest] = [:]

    func apply(_ requests: [TapRequest]) {
        let desired = Dictionary(requests.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        for (key, session) in sessions where desired[key] != session.request {
            session.stop()
            sessions[key] = nil
            Log.engine.info("Stopped tap for \(key, privacy: .public)")
        }

        failed = failed.filter { desired[$0.key] == $0.value }

        for request in requests where sessions[request.key] == nil && failed[request.key] == nil {
            do {
                sessions[request.key] = try TapSession.start(request)
                Log.engine.info("Started tap for \(request.key, privacy: .public)")
            } catch {
                failed[request.key] = request
                Log.engine.error("Could not tap \(request.key, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    func stopAll() {
        apply([])
        failed.removeAll()
    }
}

/// One app's tap, its private aggregate device and the running IOProc.
private final class TapSession {
    let request: TapRequest
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    private init(request: TapRequest) {
        self.request = request
    }

    static func start(_ request: TapRequest) throws -> TapSession {
        let session = TapSession(request: request)
        do {
            try session.setUp()
        } catch {
            session.stop()
            throw error
        }
        return session
    }

    private func setUp() throws {
        // 1. A private tap that captures the app's audio and mutes its original output while we read it.
        let description = CATapDescription(stereoMixdownOfProcesses: request.processObjectIDs)
        description.name = "Volume Rocker: \(request.key)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Create process tap")

        // 2. A private aggregate device = the real output device + the tap.
        let tapEntry: [String: Any] = [
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: description.uuid.uuidString,
        ]
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Volume Rocker \(request.key)",
            kAudioAggregateDeviceUIDKey: AudioEngine.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: request.outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: request.outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [tapEntry],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Create aggregate device")

        // 3. The real-time callback. It captures only an unretained pointer, so calling it causes no
        //    reference counting; `request` keeps the render state alive until the IOProc is destroyed.
        let state = Unmanaged.passUnretained(request.renderState)
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                state._withUnsafeGuaranteedRef { $0.render(input: input, output: output) }
            },
            "Create IOProc"
        )

        disableOutputDeviceInputs()
        try check(AudioDeviceStart(aggregateID, ioProcID), "Start audio device")
    }

    /// If the output device also has inputs (e.g. AirPods' microphone), tell Core Audio our IOProc doesn't
    /// use them. Otherwise Bluetooth headsets would drop into low-quality "call" mode.
    private func disableOutputDeviceInputs() {
        let deviceInputs = request.outputDeviceID.streamCount(scope: kAudioObjectPropertyScopeInput)
        let totalInputs = aggregateID.streamCount(scope: kAudioObjectPropertyScopeInput)
        guard deviceInputs > 0, totalInputs > deviceInputs, let ioProcID else { return }

        let headerSize = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 16
        let countOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mNumberStreams) ?? 8
        let size = headerSize + totalInputs * MemoryLayout<UInt32>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment
        )
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(totalInputs), toByteOffset: countOffset, as: UInt32.self)
        for index in 0 ..< totalInputs {
            let isOn: UInt32 = index >= deviceInputs ? 1 : 0
            raw.storeBytes(of: isOn, toByteOffset: headerSize + index * MemoryLayout<UInt32>.stride, as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), raw)
        if status != noErr {
            Log.engine.notice("Could not disable device inputs (\(status.fourCharCode, privacy: .public))")
        }
    }

    /// Tears everything down in reverse order. `AudioDeviceStop` waits for a running IOProc to return.
    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }
}
