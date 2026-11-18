import OSLog

/// Loggers for each area. View them in Console.app by filtering for "Volume Rocker".
/// Never log from the real-time audio thread.
enum Log {
    private static let subsystem = "io.github.printmoney.VolumeRocker"
    static let engine = Logger(subsystem: subsystem, category: "AudioEngine")
    static let processes = Logger(subsystem: subsystem, category: "ProcessMonitor")
    static let devices = Logger(subsystem: subsystem, category: "DeviceManager")
}
