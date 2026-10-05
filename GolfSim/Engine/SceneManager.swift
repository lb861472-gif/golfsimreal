import Foundation
import SwiftUI
import SceneKit
import AVFoundation
import UIKit
import simd

final class SceneManager: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let ballNode = SCNNode()
    private let flagNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambNode = SCNNode()
    private let waterNode = SCNNode()
    private let root = SCNNode()

    private var height: HeightField = HeightField(res: 8, width: 1, length: 1)
    private var hole: Hole?
    private var course: Course?
    private var weather: WeatherCondition = .clear
    private var cameraMode: CameraMode = .address
    private var session: GameSession?

    private var ballPos = SIMD3<Float>(0, 1, 2)
    private var ballVel = SIMD3<Float>(0, 0, 0)
    private var airborne = false
    private var rolling = false
    private var lastTime: TimeInterval = 0
    private var teePos = SIMD3<Float>(0, 0.4, 4)
    private var pinPos = SIMD3<Float>(0, 0.4, 70)
    private var worldLength: Float = 90
    private var worldWidth: Float = 56
    private var yardsScale: Float = 1
    private var flightOrigin = SIMD3<Float>(0, 0, 0)
    private var maxHeight: Float = 0
    private var waterPhase: CGFloat = 0
    private var particleHost = SCNNode()

    private let audio = ProceduralAudio()
    private var impactObs: NSObjectProtocol?
    private var practiceObs: NSObjectProtocol?
    private var holeObs: NSObjectProtocol?

    override init() {
        super.init()
        scene.rootNode.addChildNode(root)
        configureCamera()
        configureLights()
        buildBall()
        scene.background.contents = UIColor(red: 0.45, green: 0.7, blue: 0.95, alpha: 1)
        scene.fogStartDistance = 40
        scene.fogEndDistance = 140
        scene.fogDensityExponent = 1
        scene.physicsWorld.gravity = SCNVector3(0, -9.81, 0)
        audio.prepare()
        observe()
    }

    deinit {
        [impactObs, practiceObs, holeObs].compactMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    func attach(session: GameSession) {
        self.session = session
        load(hole: session.hole, course: session.course, weather: session.weather)
    }

    func load(hole: Hole, course: Course, weather: WeatherCondition) {
        self.hole = hole
        self.course = course
        self.weather = weather
        root.childNodes.forEach { $0.removeFromParentNode() }
        particleHost = SCNNode()
        root.addChildNode(particleHost)

        yardsScale = 78.0 / Float(max(120, hole.yards))
        worldLength = Float(hole.yards) * yardsScale + 16
        worldWidth = Float(hole.fairwayWidthYards) * 0.55 + 36

        height = HeightField.make(hole: hole, course: course, width: worldWidth, length: worldLength, res: 96)
        teePos = SIMD3(0, height.sample(x: 0, z: 4) + 0.12, 4)
        let pinZ = worldLength * 0.86
        pinPos = SIMD3(Float(hole.dogleg == .left ? -3 : hole.dogleg == .right ? 3 : 0), height.sample(x: 0, z: pinZ) + 0.02, pinZ)

        applyAtmosphere(course: course, weather: weather)
        root.addChildNode(makeTerrainMesh())
        addWater(course: course, hole: hole)
        addVegetation(course: course, hole: hole)
        addHazards(hole: hole)
        addFlag()
        addEnvironmentParticles(course: course, weather: weather)
        resetBall()
        cameraMode = .overview
        audio.setWind(enabled: true, intensity: hole.windBias.x * hole.windBias.x + hole.windBias.z * hole.windBias.z)
    }

    func setCamera(_ mode: CameraMode) {
        cameraMode = mode
    }

    func applySwing(_ metrics: SwingMetrics) {
        guard !metrics.isPractice, let hole else { return }
        let loft = metrics.launchAngleDeg * .pi / 180
        let yaw = metrics.launchDirectionDeg * .pi / 180
        let speedMS = metrics.clubheadSpeedMph * metrics.club.smashFactor * 0.44704
        var dir = SIMD3<Float>(-sin(yaw), sin(loft), cos(yaw) * cos(loft))
        if metrics.club == .putter {
            dir = SIMD3(-sin(yaw) * 0.15, 0.02, cos(yaw))
        }
        dir = simd_normalize(dir)
        let elev = Float(hole.elevationChangeYards) * 0.012
        ballVel = dir * speedMS * (metrics.club == .putter ? 0.22 : 0.55) * (1 + elev * 0.04)
        airborne = metrics.club != .putter
        rolling = metrics.club == .putter
        flightOrigin = ballPos
        maxHeight = ballPos.y
        audio.playImpact(putt: metrics.club == .putter)
        spawnImpactSpray()
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1 / 60 : min(1 / 20, time - lastTime)
        lastTime = time
        waterPhase += dt
        animateWater()
        stepPhysics(dt: Float(dt))
        updateCamera(dt: Float(dt))
        if let session, cameraMode != session.camera {
            cameraMode = session.camera
        }
    }

    // MARK: - Physics

    private func stepPhysics(dt: Float) {
        guard let hole, let course, let session else { return }
        guard airborne || rolling else {
            stickToGround()
            return
        }

        let windMul = weather.windMultiplier
        let wind = SIMD3<Float>(hole.windBias.x * 3.2 * windMul, 0, hole.windBias.z * 2.4 * windMul)
        if airborne {
            ballVel += SIMD3(0, -9.81, 0) * dt
            ballVel += wind * dt
            let speed = simd_length(ballVel)
            if speed > 0.1 {
                ballVel -= simd_normalize(ballVel) * speed * speed * 0.012 * dt
            }
        } else if rolling {
            ballVel += wind * 0.15 * dt
            let lieFric = session.lie.friction * hole.turfFriction
            ballVel.x *= max(0, 1 - lieFric * dt * 2.4)
            ballVel.z *= max(0, 1 - lieFric * dt * 2.4)
            ballVel.y = 0
        }

        ballPos += ballVel * dt
        let ground = height.sample(x: ballPos.x, z: ballPos.z)
        maxHeight = max(maxHeight, ballPos.y)

        if isWater(at: ballPos) && ballPos.y <= ground + 0.2 {
            audio.playSplash()
            airborne = false
            rolling = false
            ballVel = .zero
            DispatchQueue.main.async {
                session.ballLanded(carryYards: self.carryYards(), lie: .water, holed: false, penalty: true)
                self.dropNear(self.ballPos)
            }
            return
        }

        if ballPos.y <= ground + 0.08 {
            ballPos.y = ground + 0.08
            let n = height.normal(x: ballPos.x, z: ballPos.z)
            if airborne {
                let impact = -simd_dot(ballVel, n)
                let rest = session.lie.restitution
                if impact > 0.4 {
                    ballVel = ballVel - (1 + rest) * impact * n
                    ballVel.x *= 0.72
                    ballVel.z *= 0.72
                    spawnImpactSpray()
                }
                if simd_length(ballVel) < 2.2 || ballVel.y < 1.1 {
                    airborne = false
                    rolling = true
                    ballVel.y = 0
                }
            }
            if rolling && simd_length(SIMD2(ballVel.x, ballVel.z)) < 0.18 {
                rolling = false
                ballVel = .zero
                finishShot(session: session, hole: hole, course: course, ground: ground)
            }
        }

        ballPos.x = max(-worldWidth * 0.48, min(worldWidth * 0.48, ballPos.x))
        ballPos.z = max(1, min(worldLength - 1, ballPos.z))
        ballNode.position = SCNVector3(ballPos.x, ballPos.y, ballPos.z)
        ballNode.eulerAngles.x += ballVel.z * dt * 2
    }

    private func finishShot(session: GameSession, hole: Hole, course: Course, ground: Float) {
        let carry = carryYards()
        let lie = classifyLie(at: ballPos)
        let toPin = simd_length(SIMD2(ballPos.x - pinPos.x, ballPos.z - pinPos.z))
        let holed = toPin < 0.28 && lie == .green && simd_length(ballVel) < 0.4
        if holed {
            ballPos = pinPos
            ballPos.y = ground + 0.02
            ballNode.position = SCNVector3(ballPos.x, ballPos.y, ballPos.z)
        }
        DispatchQueue.main.async {
            session.ballLanded(carryYards: carry, lie: lie, holed: holed, penalty: false)
        }
    }

    private func carryYards() -> Float {
        let dx = ballPos.x - flightOrigin.x
        let dz = ballPos.z - flightOrigin.z
        let world = sqrt(dx * dx + dz * dz)
        return world / max(0.001, yardsScale)
    }

    private func classifyLie(at p: SIMD3<Float>) -> TerrainType {
        let toPin = simd_length(SIMD2(p.x - pinPos.x, p.z - pinPos.z))
        if toPin < 3.4 { return .green }
        if let hole {
            for h in hole.hazards {
                let hx = h.position.x * worldWidth * 0.4
                let hz = 6 + h.position.z * (worldLength - 12)
                let d = simd_length(SIMD2(p.x - hx, p.z - hz))
                if d < h.radius * 8 {
                    switch h.kind {
                    case .bunker, .potBunker: return .sand
                    case .waste: return .waste
                    case .water, .ocean, .creek, .lake: return .water
                    case .rock, .cliff: return .rock
                    case .trees: return course?.id == .oceanPines ? .pineNeedle : .rough
                    case .wall: return .rough
                    }
                }
            }
        }
        if abs(p.x) > Float(hole?.fairwayWidthYards ?? 30) * 0.18 {
            return course?.id == .stAndrewsBay ? .heather : .rough
        }
        return .fairway
    }

    private func isWater(at p: SIMD3<Float>) -> Bool {
        guard let hole else { return false }
        for h in hole.hazards where [.water, .ocean, .creek, .lake].contains(h.kind) {
            let hx = h.position.x * worldWidth * 0.4
            let hz = 6 + h.position.z * (worldLength - 12)
            if simd_length(SIMD2(p.x - hx, p.z - hz)) < h.radius * 9 { return true }
        }
        if course?.id == .pebbleGreens && p.x > worldWidth * 0.28 { return true }
        return false
    }

    private func stickToGround() {
        let g = height.sample(x: ballPos.x, z: ballPos.z)
        ballPos.y = g + 0.08
        ballNode.position = SCNVector3(ballPos.x, ballPos.y, ballPos.z)
    }

    private func dropNear(_ p: SIMD3<Float>) {
        ballPos = SIMD3(p.x * 0.4, height.sample(x: p.x * 0.4, z: p.z) + 0.1, p.z)
        ballNode.position = SCNVector3(ballPos.x, ballPos.y, ballPos.z)
    }

    private func resetBall() {
        ballPos = teePos
        ballVel = .zero
        airborne = false
        rolling = false
        flightOrigin = teePos
        ballNode.position = SCNVector3(teePos.x, teePos.y, teePos.z)
        flagNode.position = SCNVector3(pinPos.x, pinPos.y, pinPos.z)
    }

    // MARK: - Camera

    private func configureCamera() {
        let cam = SCNCamera()
        cam.zFar = 220
        cam.zNear = 0.05
        cam.fieldOfView = 60
        cam.wantsHDR = true
        cam.bloomIntensity = 0.18
        cam.bloomBlurRadius = 8
        cam.motionBlurIntensity = 0.15
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 8, 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func updateCamera(dt: Float) {
        let target: SCNVector3
        let look: SCNVector3
        switch cameraMode {
        case .address:
            target = SCNVector3(ballPos.x, ballPos.y + 1.35, ballPos.z - 4.2)
            look = SCNVector3(pinPos.x, pinPos.y + 0.8, pinPos.z)
        case .flight:
            let back = simd_normalize(SIMD3(ballVel.x, 0, ballVel.z) + SIMD3(0, 0, 0.01))
            target = SCNVector3(ballPos.x - back.x * 4.5, ballPos.y + 1.8, ballPos.z - back.z * 4.5)
            look = SCNVector3(ballPos.x, ballPos.y + 0.4, ballPos.z + 2)
        case .overview:
            target = SCNVector3(0, 28, worldLength * 0.15)
            look = SCNVector3(0, 0, worldLength * 0.55)
        }
        cameraNode.position = lerp(cameraNode.position, target, t: cameraMode == .flight ? 0.18 : 0.08)
        let constraintLook = look
        let current = cameraNode.position
        cameraNode.look(at: constraintLook, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        _ = (dt, current)
    }

    // MARK: - Scene build

    private func configureLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 8
        sun.shadowRadius = 3.5
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowColor = UIColor(white: 0, alpha: 0.55)
        sun.intensity = 900
        sun.temperature = 5600
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.85, 0.45, 0)
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 220
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 180
        fill.attenuationEndDistance = 80
        let fillNode = SCNNode()
        fillNode.name = "fill"
        fillNode.light = fill
        fillNode.position = SCNVector3(-12, 18, 20)
        scene.rootNode.addChildNode(fillNode)
    }

    private func applyAtmosphere(course: Course, weather: WeatherCondition) {
        let sky: (UIColor, UIColor, UIColor)
        var fog: UIColor
        var start: CGFloat = 48
        var end: CGFloat = 150
        var sunIntensity: CGFloat = 950
        var temp: CGFloat = 5600
        var sunAngle = SCNVector3(-0.85, 0.4, 0)

        switch course.id {
        case .pebbleGreens:
            sky = (UIColor(red: 0.23, green: 0.55, blue: 0.95, alpha: 1),
                   UIColor(red: 0.62, green: 0.82, blue: 0.98, alpha: 1),
                   UIColor(red: 0.90, green: 0.93, blue: 0.85, alpha: 1))
            fog = UIColor(red: 0.75, green: 0.86, blue: 0.95, alpha: 1)
        case .oceanPines:
            sky = (UIColor(red: 0.35, green: 0.40, blue: 0.42, alpha: 1),
                   UIColor(red: 0.55, green: 0.60, blue: 0.58, alpha: 1),
                   UIColor(red: 0.45, green: 0.48, blue: 0.40, alpha: 1))
            fog = UIColor(red: 0.62, green: 0.68, blue: 0.64, alpha: 1)
            start = 18; end = 90; sunIntensity = 520
        case .desertLinks:
            sky = (UIColor(red: 0.95, green: 0.45, blue: 0.18, alpha: 1),
                   UIColor(red: 0.98, green: 0.72, blue: 0.35, alpha: 1),
                   UIColor(red: 0.85, green: 0.55, blue: 0.28, alpha: 1))
            fog = UIColor(red: 0.90, green: 0.62, blue: 0.35, alpha: 1)
            temp = 3800; sunAngle = SCNVector3(-0.55, 0.85, 0); sunIntensity = 1100
        case .alpineCrest:
            sky = (UIColor(red: 0.20, green: 0.45, blue: 0.92, alpha: 1),
                   UIColor(red: 0.70, green: 0.84, blue: 0.98, alpha: 1),
                   UIColor(red: 0.92, green: 0.95, blue: 0.98, alpha: 1))
            fog = UIColor(red: 0.85, green: 0.90, blue: 0.95, alpha: 1)
            start = 30; end = 120; sunIntensity = 1050
        case .stAndrewsBay:
            sky = (UIColor(red: 0.42, green: 0.48, blue: 0.52, alpha: 1),
                   UIColor(red: 0.62, green: 0.66, blue: 0.68, alpha: 1),
                   UIColor(red: 0.55, green: 0.58, blue: 0.50, alpha: 1))
            fog = UIColor(red: 0.70, green: 0.73, blue: 0.70, alpha: 1)
            start = 22; end = 100; sunIntensity = 480
        }

        if weather == .rain || weather == .fog {
            start *= 0.45; end *= 0.55; sunIntensity *= 0.65
        }
        if weather == .goldenHour { temp = 3200; sunAngle = SCNVector3(-0.4, 1.0, 0) }

        let img = ProceduralTextures.skyGradient(top: sky.0, horizon: sky.1, bottom: sky.2)
        scene.background.contents = img
        scene.fogColor = fog
        scene.fogStartDistance = start
        scene.fogEndDistance = end
        sunNode.light?.intensity = sunIntensity * CGFloat(weather.ambientGain)
        sunNode.light?.temperature = temp
        sunNode.eulerAngles = sunAngle
        ambNode.light?.intensity = 180 * CGFloat(weather.ambientGain)
        ambNode.light?.color = fog
    }

    private func makeTerrainMesh() -> SCNNode {
        let geom = height.geometry()
        let fairway = ProceduralTextures.material(albedo: ProceduralTextures.fairway(), roughness: 0.82)
        let green = ProceduralTextures.material(albedo: ProceduralTextures.green(), roughness: 0.55, shininess: 0.45)
        let roughImg: UIImage
        switch course?.id {
        case .desertLinks: roughImg = ProceduralTextures.desertSand()
        case .stAndrewsBay: roughImg = ProceduralTextures.heather()
        case .oceanPines: roughImg = ProceduralTextures.pineNeedle()
        default: roughImg = ProceduralTextures.rough()
        }
        let rough = ProceduralTextures.material(albedo: roughImg, roughness: 0.95)
        let sand = ProceduralTextures.material(albedo: course?.id == .desertLinks ? ProceduralTextures.desertSand() : ProceduralTextures.sand(), roughness: 0.98)
        geom.materials = [fairway, green, rough, sand]
        geom.subdivisionLevel = 0
        let node = SCNNode(geometry: geom)
        node.castsShadow = true
        return node
    }

    private func addWater(course: Course, hole: Hole) {
        let plane = SCNPlane(width: CGFloat(worldWidth * 1.4), height: CGFloat(worldLength * 0.9))
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(red: 0.05, green: 0.25, blue: 0.45, alpha: 0.72)
        mat.roughness.contents = 0.08
        mat.metalness.contents = 0.35
        mat.transparent.contents = UIColor(white: 1, alpha: 0.55)
        mat.transparencyMode = .dualLayer
        mat.fresnelExponent = 2.4
        mat.shaderModifiers = [
            .surface: """
            float t = u_time;
            vec2 uv = _surface.diffuseTexcoord;
            float ripple = sin(uv.x * 28.0 + t * 1.6) * 0.04 + sin(uv.y * 22.0 - t * 1.3) * 0.04;
            _surface.normal = normalize(_surface.normal + vec3(ripple, 0.0, ripple));
            """
        ]
        plane.materials = [mat]
        waterNode.geometry = plane
        waterNode.eulerAngles.x = -.pi / 2
        let y: Float = course.id == .pebbleGreens ? -0.4 : -0.8
        waterNode.position = SCNVector3(course.id == .pebbleGreens ? worldWidth * 0.42 : 0, y, worldLength * 0.45)
        waterNode.name = "water"
        root.addChildNode(waterNode)
    }

    private func animateWater() {
        if let mat = waterNode.geometry?.firstMaterial {
            mat.normal.contents = ProceduralTextures.waterNormal(phase: waterPhase)
        }
    }

    private func addVegetation(course: Course, hole: Hole) {
        let count = course.id == .desertLinks ? 18 : 48
        for i in 0..<count {
            var rng = SplitMix64(seed: UInt64(i * 9176 + hole.number * 13))
            let x = (rng.nextSigned()) * worldWidth * 0.46
            let z = 8 + rng.nextFloat() * (worldLength - 16)
            if abs(x) < Float(hole.fairwayWidthYards) * 0.12 { continue }
            let y = height.sample(x: x, z: z)
            switch course.id {
            case .desertLinks:
                root.addChildNode(makeCactus(at: SCNVector3(x, y, z), seed: rng.next()))
            case .alpineCrest, .oceanPines, .pebbleGreens:
                root.addChildNode(makeTree(at: SCNVector3(x, y, z), alpine: course.id == .alpineCrest, seed: rng.next()))
            case .stAndrewsBay:
                if rng.nextFloat() > 0.7 {
                    root.addChildNode(makeTree(at: SCNVector3(x, y, z), alpine: false, seed: rng.next()))
                }
            }
        }
    }

    private func makeTree(at p: SCNVector3, alpine: Bool, seed: UInt64) -> SCNNode {
        let n = SCNNode()
        n.position = p
        let trunk = SCNCylinder(radius: 0.12, height: alpine ? 1.6 : 2.1)
        trunk.firstMaterial = ProceduralTextures.material(albedo: ProceduralTextures.rock(size: 64), roughness: 0.9)
        let t = SCNNode(geometry: trunk)
        t.position.y = Float(trunk.height) / 2
        t.castsShadow = true
        let foliage = SCNCone(topRadius: 0.05, bottomRadius: alpine ? 0.7 : 1.1, height: alpine ? 2.4 : 3.2)
        let img = ProceduralTextures.rough(size: 128)
        let fm = ProceduralTextures.material(albedo: img, roughness: 0.88)
        fm.diffuse.contents = alpine ? UIColor(red: 0.12, green: 0.32, blue: 0.22, alpha: 1) : UIColor(red: 0.08, green: 0.28, blue: 0.12, alpha: 1)
        foliage.materials = [fm]
        let f = SCNNode(geometry: foliage)
        f.position.y = Float(trunk.height) + Float(foliage.height) / 2 - 0.2
        f.castsShadow = true
        n.addChildNode(t)
        n.addChildNode(f)
        n.scale = SCNVector3(0.8 + Float(seed % 40) / 80, 0.85 + Float(seed % 30) / 70, 0.8)
        return n
    }

    private func makeCactus(at p: SCNVector3, seed: UInt64) -> SCNNode {
        let n = SCNNode()
        n.position = p
        let g = SCNCylinder(radius: 0.12, height: 1.4)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.22, green: 0.42, blue: 0.22, alpha: 1)
        g.materials = [m]
        let c = SCNNode(geometry: g)
        c.position.y = 0.7
        n.addChildNode(c)
        return n
    }

    private func addHazards(hole: Hole) {
        for h in hole.hazards {
            let hx = h.position.x * worldWidth * 0.4
            let hz = 6 + h.position.z * (worldLength - 12)
            let y = height.sample(x: hx, z: hz)
            switch h.kind {
            case .bunker, .potBunker, .waste:
                let r = CGFloat(max(1.2, h.radius * 7))
                let disc = SCNCylinder(radius: r, height: h.kind == .potBunker ? 0.55 : 0.18)
                disc.firstMaterial = ProceduralTextures.material(
                    albedo: h.kind == .waste ? ProceduralTextures.desertSand() : ProceduralTextures.sand(),
                    roughness: 0.99
                )
                let n = SCNNode(geometry: disc)
                n.position = SCNVector3(hx, y - 0.05, hz)
                root.addChildNode(n)
            case .rock, .cliff:
                let box = SCNBox(width: 2.2, height: 1.6, length: 2.4, chamferRadius: 0.2)
                box.firstMaterial = ProceduralTextures.material(albedo: ProceduralTextures.rock(), roughness: 0.7)
                let n = SCNNode(geometry: box)
                n.position = SCNVector3(hx, y + 0.6, hz)
                n.castsShadow = true
                root.addChildNode(n)
            case .wall:
                let box = SCNBox(width: 6, height: 0.7, length: 0.28, chamferRadius: 0)
                box.firstMaterial = ProceduralTextures.material(albedo: ProceduralTextures.rock(size: 128), roughness: 0.85)
                let n = SCNNode(geometry: box)
                n.position = SCNVector3(hx, y + 0.35, hz)
                root.addChildNode(n)
            default:
                break
            }
        }
    }

    private func addFlag() {
        flagNode.childNodes.forEach { $0.removeFromParentNode() }
        let pole = SCNCylinder(radius: 0.025, height: 2.2)
        pole.firstMaterial?.diffuse.contents = UIColor.white
        let p = SCNNode(geometry: pole)
        p.position.y = 1.1
        let flag = SCNPlane(width: 0.55, height: 0.32)
        flag.firstMaterial?.diffuse.contents = UIColor.systemRed
        flag.firstMaterial?.isDoubleSided = true
        flag.firstMaterial?.lightingModel = .constant
        let f = SCNNode(geometry: flag)
        f.position = SCNVector3(0.28, 1.95, 0)
        let cup = SCNCylinder(radius: 0.14, height: 0.04)
        cup.firstMaterial?.diffuse.contents = UIColor.white
        let c = SCNNode(geometry: cup)
        c.position.y = 0.02
        flagNode.addChildNode(p)
        flagNode.addChildNode(f)
        flagNode.addChildNode(c)
        flagNode.position = SCNVector3(pinPos.x, pinPos.y, pinPos.z)
        root.addChildNode(flagNode)
    }

    private func buildBall() {
        let sphere = SCNSphere(radius: 0.085)
        sphere.segmentCount = 36
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = ProceduralTextures.ballAlbedo()
        mat.normal.contents = ProceduralTextures.ballNormal()
        mat.roughness.contents = 0.18
        mat.metalness.contents = 0.05
        mat.specular.contents = UIColor.white
        mat.shininess = 1.4
        mat.clearCoat.contents = 0.85
        mat.clearCoatRoughness.contents = 0.12
        sphere.materials = [mat]
        ballNode.geometry = sphere
        ballNode.castsShadow = true
        scene.rootNode.addChildNode(ballNode)
    }

    private func addEnvironmentParticles(course: Course, weather: WeatherCondition) {
        particleHost.childNodes.forEach { $0.removeFromParentNode() }
        if session?.persistence.profile.reducedParticles == true { return }

        func mist(color: UIColor, birth: CGFloat) -> SCNParticleSystem {
            let p = SCNParticleSystem()
            p.birthRate = birth
            p.particleLifeSpan = 6
            p.particleSize = 0.35
            p.particleColor = color
            p.blendMode = .additive
            p.emitterShape = SCNBox(width: CGFloat(worldWidth), height: 2, length: CGFloat(worldLength * 0.6), chamferRadius: 0)
            p.spreadingAngle = 20
            p.particleVelocity = 0.4
            p.loops = true
            return p
        }

        switch course.id {
        case .pebbleGreens:
            particleHost.addParticleSystem(mist(color: UIColor(white: 1, alpha: 0.12), birth: 18))
        case .oceanPines, .stAndrewsBay:
            particleHost.addParticleSystem(mist(color: UIColor(white: 0.85, alpha: 0.18), birth: 28))
        case .desertLinks:
            let dust = mist(color: UIColor(red: 0.85, green: 0.7, blue: 0.4, alpha: 0.16), birth: 22)
            particleHost.addParticleSystem(dust)
        case .alpineCrest:
            particleHost.addParticleSystem(mist(color: UIColor(white: 1, alpha: 0.2), birth: 24))
        }
        particleHost.position = SCNVector3(0, 2.5, worldLength * 0.4)

        if weather == .rain {
            let rain = SCNParticleSystem()
            rain.birthRate = 220
            rain.particleLifeSpan = 0.9
            rain.particleSize = 0.04
            rain.particleVelocity = -18
            rain.particleColor = UIColor(white: 0.8, alpha: 0.5)
            rain.emitterShape = SCNBox(width: CGFloat(worldWidth), height: 1, length: CGFloat(worldLength), chamferRadius: 0)
            rain.loops = true
            let rainNode = SCNNode()
            rainNode.position = SCNVector3(0, 16, worldLength * 0.5)
            rainNode.addParticleSystem(rain)
            particleHost.addChildNode(rainNode)
        }
    }

    private func spawnImpactSpray() {
        let puff = SCNParticleSystem()
        puff.birthRate = 0
        puff.particleLifeSpan = 0.45
        puff.particleSize = 0.08
        puff.particleVelocity = 2.5
        puff.spreadingAngle = 70
        puff.blendMode = .alpha
        puff.loops = false
        puff.emissionDuration = 0.12
        puff.birthRate = 64
        let lie = session?.lie ?? .fairway
        puff.particleColor = (lie == .sand || lie == .waste)
            ? UIColor(red: 0.85, green: 0.75, blue: 0.5, alpha: 0.8)
            : UIColor(red: 0.25, green: 0.45, blue: 0.18, alpha: 0.7)
        ballNode.addParticleSystem(puff)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.ballNode.removeParticleSystem(puff)
        }
    }

    private func observe() {
        impactObs = NotificationCenter.default.addObserver(forName: .golfImpactSwing, object: nil, queue: .main) { [weak self] note in
            if let m = note.object as? SwingMetrics {
                self?.applySwing(m)
            }
        }
        practiceObs = NotificationCenter.default.addObserver(forName: .golfPracticeSwing, object: nil, queue: .main) { [weak self] _ in
            self?.audio.playSwish()
        }
        holeObs = NotificationCenter.default.addObserver(forName: .golfHoleOut, object: nil, queue: .main) { [weak self] _ in
            self?.audio.playCup()
        }
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, t: Float) -> SCNVector3 {
        SCNVector3(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t
        )
    }
}

struct HeightField {
    let res: Int
    let width: Float
    let length: Float
    var samples: [Float]

    func idx(_ x: Int, _ z: Int) -> Int { z * (res + 1) + x }

    func sample(x: Float, z: Float) -> Float {
        let u = (x + width * 0.5) / width
        let v = z / length
        let px = max(0, min(Float(res) - 0.001, u * Float(res)))
        let pz = max(0, min(Float(res) - 0.001, v * Float(res)))
        let x0 = Int(floor(px))
        let z0 = Int(floor(pz))
        let tx = px - Float(x0)
        let tz = pz - Float(z0)
        let a = samples[idx(x0, z0)]
        let b = samples[idx(min(res, x0 + 1), z0)]
        let c = samples[idx(x0, min(res, z0 + 1))]
        let d = samples[idx(min(res, x0 + 1), min(res, z0 + 1))]
        let ab = a + (b - a) * tx
        let cd = c + (d - c) * tx
        return ab + (cd - ab) * tz
    }

    func normal(x: Float, z: Float) -> SIMD3<Float> {
        let e: Float = 0.4
        let dx = sample(x: x + e, z: z) - sample(x: x - e, z: z)
        let dz = sample(x: x, z: z + e) - sample(x: x, z: z - e)
        return simd_normalize(SIMD3(-dx, 2 * e, -dz))
    }

    func geometry() -> SCNGeometry {
        let n = res + 1
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        var indices: [Int32] = []
        positions.reserveCapacity(n * n)
        for z in 0..<n {
            for x in 0..<n {
                let wx = (Float(x) / Float(res) - 0.5) * width
                let wz = Float(z) / Float(res) * length
                let wy = samples[idx(x, z)]
                positions.append(SCNVector3(wx, wy, wz))
                uv.append(CGPoint(x: Double(x) / Double(res) * 8, y: Double(z) / Double(res) * 12))
                let nx = normal(x: wx, z: wz)
                normals.append(SCNVector3(nx.x, nx.y, nx.z))
            }
        }
        for z in 0..<res {
            for x in 0..<res {
                let a = Int32(z * n + x)
                let b = a + 1
                let c = a + Int32(n)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let posSrc = SCNGeometrySource(vertices: positions)
        let nrmSrc = SCNGeometrySource(normals: normals)
        let uvSrc = SCNGeometrySource(textureCoordinates: uv)
        let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: idxData, primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<Int32>.size)
        let geom = SCNGeometry(sources: [posSrc, nrmSrc, uvSrc], elements: [element])
        return geom
    }

    static func make(hole: Hole, course: Course, width: Float, length: Float, res: Int) -> HeightField {
        var samples = [Float](repeating: 0, count: (res + 1) * (res + 1))
        var rng = SplitMix64(seed: UInt64(hole.number * 7919) ^ UInt64(course.par) &* 13)
        let elev = Float(hole.elevationChangeYards) * 0.045
        for z in 0...res {
            for x in 0...res {
                let u = Float(x) / Float(res)
                let v = Float(z) / Float(res)
                let wx = (u - 0.5)
                var h = ProceduralTextures.fbm(wx * 8 + Float(hole.number), v * 10, octaves: 4) * 0.65
                h += v * elev
                if course.id == .alpineCrest {
                    h += pow(v, 1.4) * elev * 0.8
                    h += ProceduralTextures.fbm(wx * 4, v * 4, octaves: 2) * 1.4
                }
                if course.id == .stAndrewsBay {
                    h += sinf(v * 14) * 0.35 + sinf(wx * 18) * 0.15
                }
                if course.id == .pebbleGreens && wx > 0.22 {
                    h -= 2.8
                }
                let fw = Float(hole.fairwayWidthYards) / 90
                let corridor = exp(-pow(wx / max(0.08, fw), 2) * 6)
                h -= corridor * 0.35
                let greenV = 0.86
                let gd = sqrt(pow(wx * 4, 2) + pow(v - greenV, 2))
                if gd < 0.12 {
                    h = (h * 0.3) + elev * greenV + Float(hole.greenTiering) * (v - greenV) * 8
                }
                samples[z * (res + 1) + x] = h
            }
        }
        _ = rng.next()
        return HeightField(res: res, width: width, length: length, samples: samples)
    }
}

final class ProceduralAudio {
    private var impact: AVAudioPlayer?
    private var swish: AVAudioPlayer?
    private var cup: AVAudioPlayer?
    private var splash: AVAudioPlayer?
    private var wind: AVAudioPlayer?
    private var enabled: Bool { PersistenceManager.shared.profile.audioEnabled }

    func prepare() {
        impact = player(Self.wav(kind: .impact))
        swish = player(Self.wav(kind: .swish))
        cup = player(Self.wav(kind: .cup))
        splash = player(Self.wav(kind: .splash))
        wind = player(Self.wav(kind: .wind))
        wind?.numberOfLoops = -1
        wind?.volume = 0.18
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func playImpact(putt: Bool) {
        guard enabled else { return }
        impact?.volume = putt ? 0.35 : 1
        impact?.currentTime = 0
        impact?.play()
    }

    func playSwish() {
        guard enabled else { return }
        swish?.currentTime = 0
        swish?.play()
    }

    func playCup() {
        guard enabled else { return }
        cup?.currentTime = 0
        cup?.play()
    }

    func playSplash() {
        guard enabled else { return }
        splash?.currentTime = 0
        splash?.play()
    }

    func setWind(enabled windOn: Bool, intensity: Float) {
        guard enabled, windOn else { wind?.stop(); return }
        wind?.volume = 0.12 + min(0.28, intensity)
        if wind?.isPlaying != true { wind?.play() }
    }

    private func player(_ data: Data) -> AVAudioPlayer? {
        try? AVAudioPlayer(data: data)
    }

    enum Kind { case impact, swish, cup, splash, wind }

    static func wav(kind: Kind) -> Data {
        let rate = 22050
        let seconds: Double
        switch kind {
        case .impact: seconds = 0.28
        case .swish: seconds = 0.32
        case .cup: seconds = 0.55
        case .splash: seconds = 0.4
        case .wind: seconds = 2.4
        }
        let n = Int(Double(rate) * seconds)
        var samples = [Int16](repeating: 0, count: n)
        var seed: UInt64 = 12345
        func rng() -> Float {
            seed = seed &* 1664525 &+ 1013904223
            return Float(seed % 10000) / 5000 - 1
        }
        for i in 0..<n {
            let t = Float(i) / Float(rate)
            let env: Float
            var s: Float = 0
            switch kind {
            case .impact:
                env = exp(-t * 18)
                s = sin(2 * .pi * 1900 * t) * 0.45 + rng() * 0.55
            case .swish:
                env = min(1, t * 12) * exp(-t * 8)
                s = rng() * 0.7
            case .cup:
                env = exp(-t * 4)
                let f: Float = t < 0.18 ? 780 : 1180
                s = sin(2 * .pi * f * t) * 0.8
            case .splash:
                env = exp(-t * 7)
                s = rng() * 0.9
            case .wind:
                env = 1
                s = rng() * 0.25
            }
            let v = max(-1, min(1, s * env))
            samples[i] = Int16(v * 20000)
        }
        return pcmWAV(samples, sampleRate: rate)
    }

    static func pcmWAV(_ samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) { var le = v.littleEndian; data.append(Data(bytes: &le, count: 2)) }
        func u32(_ v: UInt32) { var le = v.littleEndian; data.append(Data(bytes: &le, count: 4)) }
        ascii("RIFF")
        u32(UInt32(36 + dataSize))
        ascii("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        samples.withUnsafeBufferPointer { buf in
            data.append(buf.baseAddress!, count: dataSize)
        }
        return data
    }
}

struct SceneKitCourseView: UIViewRepresentable {
    @ObservedObject var manager: SceneManager
    var isPaused: Bool

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = manager.scene
        v.delegate = manager
        v.pointOfView = manager.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.backgroundColor = .black
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.isPlaying = !isPaused
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.isPlaying = !isPaused
        uiView.scene = manager.scene
    }
}
