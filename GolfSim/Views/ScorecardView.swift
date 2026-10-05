import SwiftUI

struct ScorecardView: View {
    @EnvironmentObject private var persistence: PersistenceManager
    @State private var courseFilter: CourseID?

    var body: some View {
        ZStack {
            Color(hex: "#08140F").ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Scorecards")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    filterBar
                    summary
                    courseBests
                    history
                }
                .padding(18)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                filterChip("All", nil)
                ForEach(CourseCatalog.all) { c in
                    filterChip(c.name, c.id)
                }
            }
        }
    }

    private func filterChip(_ title: String, _ id: CourseID?) -> some View {
        Button(title) { courseFilter = id }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(courseFilter == id ? Color.green.opacity(0.45) : .white.opacity(0.08), in: Capsule())
            .foregroundStyle(.white)
    }

    private var visibleRounds: [RoundRecord] {
        let all = persistence.profile.rounds.sorted { $0.startedAt > $1.startedAt }
        if let courseFilter { return all.filter { $0.courseID == courseFilter } }
        return all
    }

    private var summary: some View {
        let complete = visibleRounds.filter(\.isComplete)
        let avgSpeed = persistence.averageClubheadSpeed()
        let longest = persistence.profile.bests.values.map(\.longestDriveYards).max() ?? 0
        return HStack {
            metric("Rounds", "\(complete.count)")
            metric("Avg speed", String(format: "%.0f", avgSpeed))
            metric("Longest", String(format: "%.0f yds", longest))
        }
    }

    private var courseBests: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Course records")
                .font(.headline)
                .foregroundStyle(.white)
            ForEach(CourseCatalog.all) { course in
                if courseFilter == nil || courseFilter == course.id {
                    let b = persistence.bests(for: course.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(course.accentColor).frame(width: 8, height: 8)
                            Text(course.name).foregroundStyle(.white).font(.subheadline.bold())
                            Spacer()
                            Text(b.lowestScore.map { "\($0)" } ?? "—")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text("Drive \(String(format: "%.0f", b.longestDriveYards)) · Carry \(String(format: "%.0f", b.bestCarryYards)) · \(b.totalRounds) rounds")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round history")
                .font(.headline)
                .foregroundStyle(.white)
            if visibleRounds.isEmpty {
                Text("Play a round to fill this dashboard.")
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(visibleRounds) { round in
                roundCard(round)
            }
        }
    }

    private func roundCard(_ round: RoundRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(round.courseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(round.isComplete ? String(format: "%+d", round.toPar) : "In progress")
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text("Out \(round.frontNine) · In \(round.backNine) · Total \(round.totalStrokes)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(round.holeScores) { hs in
                    VStack(spacing: 1) {
                        Text("\(hs.holeNumber)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                        Text(hs.strokes == 0 ? "-" : "\(hs.strokes)")
                            .font(.caption2.bold())
                            .foregroundStyle(scoreColor(hs))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Text("Longest \(String(format: "%.0f", round.longestDriveYards)) yds · \(String(format: "%.0f mph", round.averageClubheadSpeed)) · \(round.weather.title)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func scoreColor(_ hs: HoleScore) -> Color {
        if hs.strokes == 0 { return .white.opacity(0.3) }
        if hs.strokes < hs.par { return Color.mint }
        if hs.strokes == hs.par { return .white }
        return Color.orange
    }

    private func metric(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading) {
            Text(k.uppercased()).font(.caption2).foregroundStyle(.white.opacity(0.45))
            Text(v).font(.title3.bold()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
