import SwiftUI

struct GameHUDView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var motion: MotionManager
    @ObservedObject var ble: BluetoothServerManager
    var onExit: () -> Void

    var body: some View {
        VStack {
            topBar
            Spacer()
            if session.mode == .remoteController {
                controllerPanel
            }
            bottomBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOLE \(session.hole.number) / 18")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                Text(session.hole.name)
                    .font(.headline)
                Text("Par \(session.hole.par) · \(session.hole.yards) yds · SI \(session.hole.handicap)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            MiniMapView(hole: session.hole, remaining: session.distanceRemainingYards)
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack {
                metric("Stroke", "\(session.strokeOnHole)")
                metric("Remain", String(format: "%.0f", session.distanceRemainingYards))
                metric("Speed", String(format: "%.0f", motion.liveAccelerationG * 18.5))
                WindCompass(bias: session.hole.windBias, weather: session.weather)
            }

            clubPicker

            HStack {
                Picker("Cam", selection: cameraBinding) {
                    Text("Address").tag(CameraMode.address)
                    Text("Flight").tag(CameraMode.flight)
                    Text("Flyover").tag(CameraMode.overview)
                }
                .pickerStyle(.segmented)

                Picker("Mode", selection: modeBinding) {
                    Text("3D").tag(PlayMode.standalone)
                    Text("BLE").tag(PlayMode.remoteController)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            if let swing = session.lastSwing {
                Text("Peak \(String(format: "%.1f", swing.peakAccelerationG)) g · \(String(format: "%.0f mph", swing.clubheadSpeedMph)) · launch \(String(format: "%.0f°", swing.launchAngleDeg))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.8))
            }

            if session.isHoleComplete {
                HStack {
                    Text("Hole complete · \(session.strokeOnHole)")
                        .font(.headline)
                    Spacer()
                    Button(session.holeIndex == 17 ? "Finish round" : "Next hole") {
                        session.nextHole()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(.white)
    }

    private var controllerPanel: some View {
        VStack(spacing: 8) {
            Text("REMOTE CONTROLLER")
                .font(.caption.weight(.bold))
                .tracking(2)
            Text(ble.stateText)
                .font(.subheadline)
            Text("Subscribers \(ble.subscriberCount)")
                .font(.caption)
            Text("3D scene off · impact packets only")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            if !ble.lastPacketJSON.isEmpty {
                Text(ble.lastPacketJSON)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(4)
                    .foregroundStyle(.mint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private var clubPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Club.allCases) { club in
                    Button(club.shortName) {
                        session.selectClub(club)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(session.club == club ? Color.white : Color.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(session.club == club ? .black : .white)
                }
            }
        }
    }

    private func metric(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            Text(v).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraBinding: Binding<CameraMode> {
        Binding(get: { session.camera }, set: { session.camera = $0 })
    }

    private var modeBinding: Binding<PlayMode> {
        Binding(get: { session.mode }, set: { session.setMode($0) })
    }
}

struct WindCompass: View {
    let bias: Vec2
    let weather: WeatherCondition
    var body: some View {
        let angle = atan2(Double(bias.x), Double(bias.z))
        VStack(spacing: 2) {
            Text("WIND")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 1)
                Image(systemName: "location.north.fill")
                    .font(.caption)
                    .rotationEffect(.radians(angle))
            }
            .frame(width: 28, height: 28)
            Text(weather.title)
                .font(.system(size: 8))
        }
    }
}

struct MiniMapView: View {
    let hole: Hole
    let remaining: Float
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.45)))
            var fairway = Path()
            fairway.addEllipse(in: CGRect(x: size.width * 0.28, y: 6, width: size.width * 0.44, height: size.height - 12))
            ctx.fill(fairway, with: .color(.green.opacity(0.55)))
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.42, y: 8, width: 12, height: 12)), with: .color(.mint))
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.44, y: size.height - 16, width: 8, height: 8)), with: .color(.white))
            for h in hole.hazards {
                let x = (0.5 + CGFloat(h.position.x) * 0.35) * size.width
                let y = (1 - CGFloat(h.position.z)) * size.height
                let color: Color = {
                    switch h.kind {
                    case .water, .ocean, .creek, .lake: return .blue
                    case .bunker, .potBunker, .waste: return .yellow
                    case .rock, .cliff, .wall: return .gray
                    default: return .green.opacity(0.3)
                    }
                }()
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
        .frame(width: 72, height: 92)
        .overlay(alignment: .bottom) {
            Text(String(format: "%.0f", remaining))
                .font(.system(size: 9, weight: .bold))
                .padding(2)
                .foregroundStyle(.white)
        }
    }
}
