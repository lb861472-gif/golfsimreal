# GolfSim

GolfSim is a SwiftUI iOS golf simulator with five generated 18-hole courses, locally saved scorecards, a SceneKit course renderer, CoreMotion swing measurement, and an optional BLE controller mode.

## Build

Open `GolfSim.xcodeproj` in Xcode 15 or newer on macOS, select the `GolfSim` scheme, and build for an iOS device or simulator. The project targets iOS 17 and uses only Apple frameworks.

An unsigned iOS IPA can be built from GitHub Actions. Push to `main` or `master`, open the **Actions** tab, and download the `GolfSim-unsigned-ipa` artifact from a completed run. You can also start a run manually with **Build Unsigned IPA** under **Actions**. The IPA is unsigned and must be installed using a compatible sideloading workflow; it is not App Store-ready.

## Gameplay

- **Standalone 3D** measures swings on-device and simulates shots in SceneKit.
- **BLE Controller** disables the 3D scene and sends finalized swing metrics through the advertised GATT service and notify characteristic. Raw 100 Hz motion samples are never streamed.
- Round history, hole-by-hole scores, course records, settings, and swing history are stored locally on the device.

The BLE identifiers are defined in `GolfSim/Services/BluetoothServerManager.swift`. Motion and Bluetooth permissions are declared in `GolfSim/Info.plist`.