import Foundation
import CoreMotion
import Combine

final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    @Published var liveAccelerationG: Float = 0
    @Published var liveGyro: Float = 0
    @Published var isTracking = false
    @Published var lastMetrics: SwingMetrics?

    var onImpact: ((SwingMetrics) -> Void)?
    var onPractice: ((SwingMetrics) -> Void)?

    var selectedClub: Club = .driver

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let sampleHz: Double = 100

    private var peakAccel: Float = 0
    private var peakGyro: Float = 0
    private var armed = false
    private var cooldownUntil: TimeInterval = 0
    private var yawAtAddress: Double = 0
    private var lastPracticeAt: TimeInterval = 0

    private let impactG: Float = 2.35
    private let practiceG: Float = 1.15

    private init() {
        queue.name = "golfsim.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        stop()
        peakAccel = 0
        peakGyro = 0
        armed = true
        motion.deviceMotionUpdateInterval = 1.0 / sampleHz
        motion.showsDeviceMovementDisplay = false
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.process(data)
        }
        DispatchQueue.main.async { self.isTracking = true }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        DispatchQueue.main.async { self.isTracking = false }
    }

    func resetAddress() {
        yawAtAddress = motion.deviceMotion?.attitude.yaw ?? yawAtAddress
        peakAccel = 0
        peakGyro = 0
        armed = true
    }

    private func process(_ data: CMDeviceMotion) {
        let ua = data.userAcceleration
        let mag = Float(sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z))
        let gyr = data.rotationRate
        let gyroMag = Float(sqrt(gyr.x * gyr.x + gyr.y * gyr.y + gyr.z * gyr.z))
        let now = data.timestamp

        peakAccel = max(peakAccel, mag)
        peakGyro = max(peakGyro, gyroMag)

        DispatchQueue.main.async {
            self.liveAccelerationG = mag
            self.liveGyro = gyroMag
        }

        guard now >= cooldownUntil else { return }

        let yawDelta = Float((data.attitude.yaw - yawAtAddress) * 180 / .pi)
        let direction = max(-45, min(45, yawDelta * 0.85))

        if armed && mag >= impactG && peakAccel > impactG {
            armed = false
            cooldownUntil = now + 0.85
            let metrics = SwingMetrics.impact(
                peakG: peakAccel,
                gyro: peakGyro,
                club: selectedClub,
                direction: direction,
                practice: false
            )
            peakAccel = 0
            peakGyro = 0
            DispatchQueue.main.async {
                self.lastMetrics = metrics
                self.onImpact?(metrics)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.armed = true
            }
            return
        }

        if mag >= practiceG && mag < impactG && now - lastPracticeAt > 0.55 {
            lastPracticeAt = now
            let metrics = SwingMetrics.impact(
                peakG: mag,
                gyro: gyroMag,
                club: selectedClub,
                direction: direction,
                practice: true
            )
            DispatchQueue.main.async {
                self.onPractice?(metrics)
            }
        }
    }
}
