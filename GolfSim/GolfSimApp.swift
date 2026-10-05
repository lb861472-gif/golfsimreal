import SwiftUI

@main
struct GolfSimApp: App {
    @StateObject private var persistence = PersistenceManager.shared
    @StateObject private var motion = MotionManager.shared
    @StateObject private var ble = BluetoothServerManager.shared

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(persistence)
                .environmentObject(motion)
                .environmentObject(ble)
                .preferredColorScheme(.dark)
                .onAppear {
                    ble.startAdvertisingIfNeeded()
                }
        }
    }
}
