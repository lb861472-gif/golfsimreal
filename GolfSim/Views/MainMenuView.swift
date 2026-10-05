import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject private var persistence: PersistenceManager
    @EnvironmentObject private var ble: BluetoothServerManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        quickPlay
                        courseStrip
                        recordsCard
                        settingsRow
                        blePill
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .courses:
                    CourseSelectView()
                case .records:
                    ScorecardView()
                case .settings:
                    SettingsView()
                case .play(let courseID, let weather, let mode):
                    GameContainer(
                        course: CourseCatalog.course(id: courseID),
                        weather: weather,
                        mode: mode
                    )
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(hex: "#071510"),
                Color(hex: "#0C2A22"),
                Color(hex: "#163A28")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(colors: [Color.green.opacity(0.18), .clear], center: .topTrailing, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOLFSIM")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.55))
            Text("Championship\n3D Simulator")
                .font(.system(size: 38, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineSpacing(2)
            Text("Five 18-hole courses · 90 unique holes · BLE controller")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.top, 12)
    }

    private var quickPlay: some View {
        let featured = CourseCatalog.all[0]
        return VStack(spacing: 12) {
            Button {
                path.append(Destination.play(featured.id, featured.defaultWeather, persistence.profile.preferredMode))
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#1B6CA8"), Color(hex: "#0E3A2A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 168)
                        .overlay(
                            Image(systemName: "figure.golf")
                                .font(.system(size: 90))
                                .foregroundStyle(.white.opacity(0.12))
                                .offset(x: 90, y: -10)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUICK PLAY")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(featured.name)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        Text("Hole 1 · \(featured.holes[0].name) · Par \(featured.par)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(22)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                menuTile("Course Select", "map.fill", Color(hex: "#2E8B57")) {
                    path.append(Destination.courses)
                }
                menuTile("Scorecards", "list.clipboard.fill", Color(hex: "#C4A35A")) {
                    path.append(Destination.records)
                }
            }
        }
    }

    private var courseStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tour roster")
                .font(.headline)
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CourseCatalog.all) { course in
                        Button {
                            path.append(Destination.play(course.id, course.defaultWeather, persistence.profile.preferredMode))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Circle()
                                    .fill(course.accentColor)
                                    .frame(width: 12, height: 12)
                                Text(course.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Par \(course.par) · \(course.totalYards) yds")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(14)
                            .frame(width: 150, alignment: .leading)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recordsCard: some View {
        let rounds = persistence.profile.rounds
        let best = rounds.filter(\.isComplete).min(by: { $0.toPar < $1.toPar })
        return VStack(alignment: .leading, spacing: 10) {
            Text("Personal records")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                stat("Rounds", "\(rounds.filter(\.isComplete).count)")
                stat("Best", best.map { $0.toPar == 0 ? "E" : String(format: "%+d", $0.toPar) } ?? "—")
                stat("Speed", String(format: "%.0f mph", persistence.averageClubheadSpeed()))
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var settingsRow: some View {
        Button { path.append(Destination.settings) } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                Text("Settings & controller")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var blePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ble.isAdvertising ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(ble.stateText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("GATT 12345678…")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 4)
    }

    private func menuTile(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Destination: Hashable {
    case courses
    case records
    case settings
    case play(CourseID, WeatherCondition, PlayMode)
}
