import Foundation

enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case standalone
    case remoteController

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standalone: return "Standalone 3D"
        case .remoteController: return "BLE Controller"
        }
    }

    var subtitle: String {
        switch self {
        case .standalone: return "On-device SceneKit + CoreMotion"
        case .remoteController: return "Phone as swing stick — scene off"
        }
    }
}

enum Club: String, Codable, CaseIterable, Identifiable {
    case driver, wood3, iron5, iron7, pitchingWedge, sandWedge, putter

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .driver: return "DR"
        case .wood3: return "3W"
        case .iron5: return "5I"
        case .iron7: return "7I"
        case .pitchingWedge: return "PW"
        case .sandWedge: return "SW"
        case .putter: return "PT"
        }
    }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3 Wood"
        case .iron5: return "5 Iron"
        case .iron7: return "7 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .sandWedge: return "Sand Wedge"
        case .putter: return "Putter"
        }
    }

    var loftDegrees: Float {
        switch self {
        case .driver: return 10.5
        case .wood3: return 15
        case .iron5: return 25
        case .iron7: return 34
        case .pitchingWedge: return 46
        case .sandWedge: return 56
        case .putter: return 3
        }
    }

    var smashFactor: Float {
        switch self {
        case .driver: return 1.48
        case .wood3: return 1.42
        case .iron5: return 1.35
        case .iron7: return 1.30
        case .pitchingWedge: return 1.22
        case .sandWedge: return 1.15
        case .putter: return 1.05
        }
    }

    var typicalCarryYards: Int {
        switch self {
        case .driver: return 260
        case .wood3: return 225
        case .iron5: return 185
        case .iron7: return 155
        case .pitchingWedge: return 120
        case .sandWedge: return 85
        case .putter: return 30
        }
    }
}

struct SwingMetrics: Codable, Hashable, Identifiable {
    var id: UUID
    var timestamp: Date
    var peakAccelerationG: Float
    var peakGyro: Float
    var clubheadSpeedMph: Float
    var launchAngleDeg: Float
    var launchDirectionDeg: Float
    var smashQuality: Float
    var isPractice: Bool
    var club: Club

    var carryEstimateYards: Float {
        let speedFactor = clubheadSpeedMph / 110.0
        return Float(club.typicalCarryYards) * max(0.15, speedFactor) * smashQuality
    }

    static func impact(
        peakG: Float,
        gyro: Float,
        club: Club,
        direction: Float,
        practice: Bool
    ) -> SwingMetrics {
        let speed = min(145, max(8, peakG * 18.5 + gyro * 4.2))
        let loftBoost = club.loftDegrees * 0.55
        let dynamicLoft = loftBoost + min(12, peakG)
        return SwingMetrics(
            id: UUID(),
            timestamp: Date(),
            peakAccelerationG: peakG,
            peakGyro: gyro,
            clubheadSpeedMph: speed,
            launchAngleDeg: practice ? 0 : dynamicLoft,
            launchDirectionDeg: direction,
            smashQuality: min(1.15, 0.72 + peakG / 40),
            isPractice: practice,
            club: club
        )
    }
}

struct HoleScore: Codable, Hashable, Identifiable {
    var id: UUID
    var holeNumber: Int
    var par: Int
    var strokes: Int
    var putts: Int
    var penalties: Int
    var fairwayHit: Bool
    var gir: Bool
    var longestDriveYards: Float
    var bestCarryYards: Float

    var toPar: Int { strokes - par }

    static func empty(hole: Hole) -> HoleScore {
        HoleScore(
            id: UUID(),
            holeNumber: hole.number,
            par: hole.par,
            strokes: 0,
            putts: 0,
            penalties: 0,
            fairwayHit: false,
            gir: false,
            longestDriveYards: 0,
            bestCarryYards: 0
        )
    }
}

struct RoundRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var courseID: CourseID
    var courseName: String
    var startedAt: Date
    var finishedAt: Date?
    var weather: WeatherCondition
    var playMode: PlayMode
    var holeScores: [HoleScore]
    var averageClubheadSpeed: Float
    var longestDriveYards: Float
    var bestCarryYards: Float

    var totalStrokes: Int { holeScores.reduce(0) { $0 + $1.strokes } }
    var frontNine: Int { holeScores.prefix(9).reduce(0) { $0 + $1.strokes } }
    var backNine: Int { holeScores.suffix(9).reduce(0) { $0 + $1.strokes } }
    var coursePar: Int { holeScores.reduce(0) { $0 + $1.par } }
    var toPar: Int { totalStrokes - coursePar }
    var holesPlayed: Int { holeScores.filter { $0.strokes > 0 }.count }
    var isComplete: Bool { holesPlayed == 18 }

    static func fresh(course: Course, weather: WeatherCondition, mode: PlayMode) -> RoundRecord {
        RoundRecord(
            id: UUID(),
            courseID: course.id,
            courseName: course.name,
            startedAt: Date(),
            finishedAt: nil,
            weather: weather,
            playMode: mode,
            holeScores: course.holes.map { HoleScore.empty(hole: $0) },
            averageClubheadSpeed: 0,
            longestDriveYards: 0,
            bestCarryYards: 0
        )
    }
}

struct CourseBests: Codable, Hashable {
    var courseID: CourseID
    var lowestScore: Int?
    var lowestToPar: Int?
    var longestDriveYards: Float
    var bestCarryYards: Float
    var totalRounds: Int
    var holeBests: [Int: Int]

    static func empty(_ id: CourseID) -> CourseBests {
        CourseBests(
            courseID: id,
            lowestScore: nil,
            lowestToPar: nil,
            longestDriveYards: 0,
            bestCarryYards: 0,
            totalRounds: 0,
            holeBests: [:]
        )
    }
}

struct PlayerProfile: Codable, Hashable {
    var displayName: String
    var hapticsEnabled: Bool
    var audioEnabled: Bool
    var reducedParticles: Bool
    var useYards: Bool
    var preferredMode: PlayMode
    var rounds: [RoundRecord]
    var bests: [String: CourseBests]
    var swingLog: [SwingMetrics]

    static let `default` = PlayerProfile(
        displayName: "Player",
        hapticsEnabled: true,
        audioEnabled: true,
        reducedParticles: false,
        useYards: true,
        preferredMode: .standalone,
        rounds: [],
        bests: [:],
        swingLog: []
    )
}
