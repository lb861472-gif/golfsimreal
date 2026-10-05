import SwiftUI

struct GameContainer: View {
    let course: Course
    let weather: WeatherCondition
    let mode: PlayMode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var motion: MotionManager
    @EnvironmentObject private var ble: BluetoothServerManager
    @StateObject private var session: GameSession
    @State private var sceneManager: SceneManager?

    init(course: Course, weather: WeatherCondition, mode: PlayMode) {
        self.course = course
        self.weather = weather
        self.mode = mode
        _session = StateObject(wrappedValue: GameSession(course: course, weather: weather, mode: mode))
    }

    var body: some View {
        ZStack {
            if session.mode == .standalone {
                if let sceneManager {
                    SceneKitCourseView(manager: sceneManager, isPaused: false)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            } else {
                LinearGradient(colors: [Color(hex: "#102018"), Color.black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            GameHUDView(session: session, motion: motion, ble: ble) {
                session.teardown()
                dismiss()
            }

            if session.isRoundComplete {
                roundComplete
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if session.mode == .standalone { activateScene() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                session.camera = .address
                sceneManager?.setCamera(.address)
            }
        }
        .onChange(of: session.holeIndex) { _, _ in
            sceneManager?.load(hole: session.hole, course: session.course, weather: session.weather)
        }
        .onChange(of: session.mode) { _, mode in
            if mode == .standalone {
                activateScene()
            } else {
                sceneManager = nil
            }
        }
        .onChange(of: session.camera) { _, mode in
            sceneManager?.setCamera(mode)
        }
        .onDisappear {
            session.teardown()
            sceneManager = nil
        }
    }

    private func activateScene() {
        let manager = sceneManager ?? SceneManager()
        sceneManager = manager
        manager.attach(session: session)
        manager.setCamera(.overview)
    }

    private var roundComplete: some View {
        VStack(spacing: 14) {
            Text("Round complete")
                .font(.largeTitle.bold())
            Text("\(session.round.totalStrokes)  (\(String(format: "%+d", session.round.toPar)))")
                .font(.title)
            Text("Out \(session.round.frontNine) · In \(session.round.backNine)")
            Button("Return to clubhouse") {
                session.teardown()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var persistence: PersistenceManager
    @EnvironmentObject private var ble: BluetoothServerManager

    var body: some View {
        Form {
            Section("Player") {
                TextField("Name", text: nameBinding)
            }
            Section("Feedback") {
                Toggle("Haptics", isOn: hapticsBinding)
                Toggle("Audio cues", isOn: audioBinding)
                Toggle("Reduced particles", isOn: particlesBinding)
                Toggle("Yards (off = meters)", isOn: yardsBinding)
            }
            Section("Play") {
                Picker("Default mode", selection: modeBinding) {
                    ForEach(PlayMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
            }
            Section("Bluetooth controller") {
                LabeledContent("Status", value: ble.stateText)
                LabeledContent("Subscribers", value: "\(ble.subscriberCount)")
                LabeledContent("Service", value: "12345678-1234-5678-1234-567812345678")
                LabeledContent("Notify", value: "87654321-4321-6789-4321-678943218765")
                Text("Motion is sampled at 100 Hz on device. Only finalized impact payloads are notified — never a raw 100 Hz stream.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Start advertising") { ble.startAdvertisingIfNeeded() }
                Button("Stop advertising", role: .destructive) { ble.stopAdvertising() }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color(hex: "#0A1610").ignoresSafeArea())
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { persistence.profile.displayName },
            set: { v in persistence.updateSettings { $0.displayName = v } }
        )
    }
    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { persistence.profile.hapticsEnabled },
            set: { v in persistence.updateSettings { $0.hapticsEnabled = v } }
        )
    }
    private var audioBinding: Binding<Bool> {
        Binding(
            get: { persistence.profile.audioEnabled },
            set: { v in persistence.updateSettings { $0.audioEnabled = v } }
        )
    }
    private var particlesBinding: Binding<Bool> {
        Binding(
            get: { persistence.profile.reducedParticles },
            set: { v in persistence.updateSettings { $0.reducedParticles = v } }
        )
    }
    private var yardsBinding: Binding<Bool> {
        Binding(
            get: { persistence.profile.useYards },
            set: { v in persistence.updateSettings { $0.useYards = v } }
        )
    }
    private var modeBinding: Binding<PlayMode> {
        Binding(
            get: { persistence.profile.preferredMode },
            set: { v in persistence.updateSettings { $0.preferredMode = v } }
        )
    }
}
