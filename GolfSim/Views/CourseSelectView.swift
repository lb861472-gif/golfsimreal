import SwiftUI

struct CourseSelectView: View {
    @EnvironmentObject private var persistence: PersistenceManager
    @State private var selected: Course = CourseCatalog.all[0]
    @State private var weather: WeatherCondition = CourseCatalog.all[0].defaultWeather
    @State private var mode: PlayMode = .standalone

    var body: some View {
        ZStack {
            selected.accentColor.opacity(0.35).ignoresSafeArea()
            Color.black.opacity(0.72).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Select course")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CourseCatalog.all) { course in
                                courseCard(course)
                            }
                        }
                    }

                    overview
                    mapGrid
                    weatherBar
                    modeBar

                    NavigationLink {
                        GameContainer(course: selected, weather: weather, mode: mode)
                    } label: {
                        Text("Play \(selected.name)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(selected.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { mode = persistence.profile.preferredMode }
    }

    private func courseCard(_ course: Course) -> some View {
        Button {
            selected = course
            weather = course.defaultWeather
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(course.subtitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                Text(course.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Par \(course.par)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
            .frame(width: 168, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(course.id == selected.id ? course.accentColor.opacity(0.55) : .white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(course.id == selected.id ? Color.white.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var overview: some View {
        let bests = persistence.bests(for: selected.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text(selected.location)
                .foregroundStyle(.white.opacity(0.7))
            Text(selected.climate)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            HStack {
                chip("Par \(selected.par)")
                chip("\(selected.totalYards) yds")
                chip("Slope \(selected.slope)")
                chip("CR \(String(format: "%.1f", selected.rating))")
            }
            HStack {
                chip("Front \(selected.frontNinePar)")
                chip("Back \(selected.backNinePar)")
                chip(String(repeating: "♦", count: selected.difficulty))
            }
            HStack {
                chip("Low: \(bests.lowestScore.map(String.init) ?? "—")")
                chip("Drive: \(String(format: "%.0f", bests.longestDriveYards)) yds")
                chip("Rounds: \(bests.totalRounds)")
            }
        }
    }

    private var mapGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("18-hole card")
                .font(.headline)
                .foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                ForEach(selected.holes) { hole in
                    VStack(spacing: 2) {
                        Text("\(hole.number)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(hole.par)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text(selected.holes[0].notes)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var weatherBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weather & lighting")
                .font(.headline)
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(selected.weatherOptions) { w in
                        Button(w.title) { weather = w }
                            .buttonStyle(.borderedProminent)
                            .tint(weather == w ? selected.accentColor : .white.opacity(0.15))
                    }
                }
            }
        }
    }

    private var modeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Play mode")
                .font(.headline)
                .foregroundStyle(.white)
            Picker("Mode", selection: $mode) {
                ForEach(PlayMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Text(mode.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule())
            .foregroundStyle(.white)
    }
}
