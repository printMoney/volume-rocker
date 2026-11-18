import Foundation

/// Names of the distributed notifications the Control Center control posts to the app.
/// (Duplicated in the VolumeRockerControls extension, which is a separate module.)
enum ControlCenterRequest {
    static let nextProfile = Notification.Name("io.github.printmoney.VolumeRocker.nextProfile")
    static let openMixer = Notification.Name("io.github.printmoney.VolumeRocker.openMixer")
}
