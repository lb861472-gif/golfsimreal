import Foundation
import Combine
import UIKit

final class GameSession: ObservableObject {
    @Published var course: Course
    @Published var holeIndex: Int = 0
    @Published var weather: WeatherCondition
    @Published var mode: PlayMode
    @Published var club: Club = .driver
    @Published var round: RoundRecord
    @Published var strokeOnHole: Int = 0
    @Published var puttsOnHole: Int = 0
    @Published var ballInFlight = false
    @Published var lie: TerrainType = .tee
    @Published var camera: CameraMode = .address
    @Published var lastSwing: SwingMetrics?
    @Published var distanceRemainingYards: Float = 0
    @Published var shotCarryYards: Float = 0
    @Published var isHoleComplete = false
    @Published var isRoundComplete = false
    @Published var showFlyover = true

    let persistence: PersistenceManager
    let motion: MotionManager
    let ble: BluetoothServerManager
    private var speedSampleCount = 0

    var hole: Hole { course.holes[holeIndex] }

    init(
        course: Course,
        weather: WeatherCondition,
        mode: PlayMode,
        persistence: PersistenceManager = .shared,
        motion: MotionManager = .shared,
        ble: BluetoothServerManager = .shared
    ) {
        self.course = course
        self.weather = weather
        self.mode = mode
        self.persistence = persistence
        self.motion = motion
        self.ble = ble
        self.round = RoundRecord.fresh(course: course, weather: weather, mode: mode)
        self.distanceRemainingYards = Float(course.holes[0].yards)
        bindMotion()
        if mode == .remoteController {
            ble.startAdvertisingIfNeeded()
        }
        motion.selectedClub = club
        motion.start()
    }

    func bindMotion() {
        motion.onImpact = { [weak self] metrics in
            Task { @MainActor in
                self?.handleImpact(metrics)
            }
        }
        motion.onPractice = { [weak self] metrics in
            Task { @MainActor in
                self?.handlePractice(metrics)
            }
        }
    }

    func selectClub(_ club: Club) {
        self.club = club
        motion.selectedClub = club
    }

    func setMode(_ mode: PlayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        round.playMode = mode
        if mode == .remoteController {
            ballInFlight = false
            ble.startAdvertisingIfNeeded()
        } else {
            motion.resetAddress()
        }
    }

    func handlePractice(_ metrics: SwingMetrics) {
        lastSwing = metrics
        if persistence.profile.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        NotificationCenter.default.post(name: .golfPracticeSwing, object: metrics)
    }

    func handleImpact(_ metrics: SwingMetrics) {
        guard !isHoleComplete, !ballInFlight else { return }
        lastSwing = metrics

        if persistence.profile.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        persistence.recordSwing(metrics)
        if mode == .remoteController {
            ble.broadcastImpact(metrics)
            return
        }

        strokeOnHole += 1
        if club == .putter { puttsOnHole += 1 }
        ballInFlight = true
        camera = .flight
        showFlyover = false

        let count = Float(speedSampleCount)
        round.averageClubheadSpeed =
            (round.averageClubheadSpeed * count + metrics.clubheadSpeedMph) / (count + 1)
        speedSampleCount += 1

        NotificationCenter.default.post(name: .golfImpactSwing, object: metrics)
        persistence.saveRound(round)
    }

    func ballLanded(carryYards: Float, lie: TerrainType, holed: Bool, penalty: Bool) {
        ballInFlight = false
        shotCarryYards = carryYards
        self.lie = lie
        distanceRemainingYards = max(0, distanceRemainingYards - carryYards)

        if penalty {
            strokeOnHole += 1
            var hs = round.holeScores[holeIndex]
            hs.penalties += 1
            round.holeScores[holeIndex] = hs
        }

        var hs = round.holeScores[holeIndex]
        hs.bestCarryYards = max(hs.bestCarryYards, carryYards)
        round.bestCarryYards = max(round.bestCarryYards, carryYards)
        if club == .driver {
            hs.longestDriveYards = max(hs.longestDriveYards, carryYards)
            round.longestDriveYards = max(round.longestDriveYards, carryYards)
        }
        round.holeScores[holeIndex] = hs

        if holed {
            completeHole()
        } else {
            camera = .address
            motion.resetAddress()
            autoClub()
        }
        persistence.saveRound(round)
    }

    func completeHole() {
        isHoleComplete = true
        camera = .overview
        var hs = round.holeScores[holeIndex]
        hs.strokes = strokeOnHole
        hs.putts = puttsOnHole
        hs.gir = strokeOnHole - puttsOnHole <= max(1, hole.par - 2)
        hs.fairwayHit = lie == .fairway || lie == .green
        round.holeScores[holeIndex] = hs
        persistence.saveRound(round)
        NotificationCenter.default.post(name: .golfHoleOut, object: hole)
        if persistence.profile.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func nextHole() {
        guard holeIndex < 17 else {
            finishRound()
            return
        }
        holeIndex += 1
        strokeOnHole = 0
        puttsOnHole = 0
        isHoleComplete = false
        lie = .tee
        ballInFlight = false
        camera = .overview
        showFlyover = true
        distanceRemainingYards = Float(hole.yards)
        autoClub()
        motion.resetAddress()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.camera = .address
            self?.showFlyover = false
        }
    }

    func finishRound() {
        isRoundComplete = true
        round.finishedAt = Date()
        persistence.saveRound(round)
    }

    func concedeHole() {
        strokeOnHole = max(strokeOnHole + 1, hole.par + 3)
        completeHole()
    }

    func dropFromHazard() {
        strokeOnHole += 1
        var hs = round.holeScores[holeIndex]
        hs.penalties += 1
        round.holeScores[holeIndex] = hs
        lie = .fairway
        persistence.saveRound(round)
    }

    private func autoClub() {
        let d = distanceRemainingYards
        let next: Club
        if lie == .green || d < 12 { next = .putter }
        else if d < 70 { next = .sandWedge }
        else if d < 115 { next = .pitchingWedge }
        else if d < 155 { next = .iron7 }
        else if d < 190 { next = .iron5 }
        else if d < 230 { next = .wood3 }
        else { next = .driver }
        selectClub(next)
    }

    func teardown() {
        motion.stop()
        motion.onImpact = nil
        motion.onPractice = nil
    }
}

extension Notification.Name {
    static let golfImpactSwing = Notification.Name("golfsim.impact")
    static let golfPracticeSwing = Notification.Name("golfsim.practice")
    static let golfHoleOut = Notification.Name("golfsim.holeout")
}

enum CameraMode: String, CaseIterable {
    case address, flight, overview
}
