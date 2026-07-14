import CoreMotion
import Foundation

/// Device attitude for the tilt games (Spirit Level, Pour It). Updates are
/// started while a tilt game is on screen and read synchronously from the
/// view's render tick — no handler hop, no permission, no plist key
/// (device motion needs none). On the Simulator device motion is
/// unavailable, so roll/pitch read 0 and these games need a real device.
@MainActor
final class MotionService {
    static let shared = MotionService()

    private let manager = CMMotionManager()

    private init() {
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Left–right tilt in degrees.
    var rollDegrees: Double {
        (manager.deviceMotion?.attitude.roll ?? 0) * 180 / .pi
    }

    /// Front–back tilt in degrees (positive = top edge tipped away from you).
    var pitchDegrees: Double {
        (manager.deviceMotion?.attitude.pitch ?? 0) * 180 / .pi
    }

    /// Twist rate about the screen-normal axis, in degrees/second — the
    /// "turn the safe dial" motion for Crack the Safe.
    var twistRateDegrees: Double {
        (manager.deviceMotion?.rotationRate.z ?? 0) * 180 / .pi
    }
}
