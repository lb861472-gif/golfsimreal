import Foundation
import Combine

final class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    @Published var profile: PlayerProfile

    private let fileURL: URL
    private let queue = DispatchQueue(label: "golfsim.persistence", qos: .utility)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = docs.appendingPathComponent("golfsim-profile.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(PlayerProfile.self, from: data) {
            profile = decoded
        } else if let data = UserDefaults.standard.data(forKey: "golfsim.profile"),
                  let decoded = try? decoder.decode(PlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .default
        }
    }

    func bests(for course: CourseID) -> CourseBests {
        profile.bests[course.rawValue] ?? .empty(course)
    }

    func rounds(for course: CourseID) -> [RoundRecord] {
        profile.rounds.filter { $0.courseID == course }.sorted { $0.startedAt > $1.startedAt }
    }

    func saveRound(_ round: RoundRecord) {
        var next = profile
        if let idx = next.rounds.firstIndex(where: { $0.id == round.id }) {
            next.rounds[idx] = round
        } else {
            next.rounds.insert(round, at: 0)
        }
        next.rounds = Array(next.rounds.prefix(80))

        var bests = next.bests[round.courseID.rawValue] ?? .empty(round.courseID)
        let wasComplete = profile.rounds.first(where: { $0.id == round.id })?.isComplete ?? false
        if round.isComplete {
            if !wasComplete { bests.totalRounds += 1 }
            if let low = bests.lowestScore {
                bests.lowestScore = min(low, round.totalStrokes)
            } else {
                bests.lowestScore = round.totalStrokes
            }
            bests.lowestToPar = min(bests.lowestToPar ?? round.toPar, round.toPar)
            for hs in round.holeScores where hs.strokes > 0 {
                let current = bests.holeBests[hs.holeNumber]
                bests.holeBests[hs.holeNumber] = current.map { min($0, hs.strokes) } ?? hs.strokes
            }
        }
        bests.longestDriveYards = max(bests.longestDriveYards, round.longestDriveYards)
        bests.bestCarryYards = max(bests.bestCarryYards, round.bestCarryYards)
        next.bests[round.courseID.rawValue] = bests
        profile = next
        persist()
    }

    func recordSwing(_ metrics: SwingMetrics) {
        var next = profile
        next.swingLog.insert(metrics, at: 0)
        next.swingLog = Array(next.swingLog.prefix(250))
        profile = next
        persist()
    }

    func updateSettings(_ mutate: (inout PlayerProfile) -> Void) {
        var next = profile
        mutate(&next)
        profile = next
        persist()
    }

    func averageClubheadSpeed() -> Float {
        let speeds = profile.swingLog.filter { !$0.isPractice }.map(\.clubheadSpeedMph)
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Float(speeds.count)
    }

    private func persist() {
        let snapshot = profile
        let url = fileURL
        let enc = encoder
        queue.async {
            do {
                let data = try enc.encode(snapshot)
                try data.write(to: url, options: [.atomic])
                UserDefaults.standard.set(data, forKey: "golfsim.profile")
            } catch {
                UserDefaults.standard.set(try? enc.encode(snapshot), forKey: "golfsim.profile")
            }
        }
    }
}
