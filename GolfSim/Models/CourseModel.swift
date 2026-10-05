import Foundation
import SwiftUI

enum TerrainType: String, Codable, CaseIterable, Identifiable {
    case tee, fairway, rough, green, sand, water, heather, waste, rock, pineNeedle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tee: return "Tee"
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .green: return "Green"
        case .sand: return "Bunker"
        case .water: return "Water"
        case .heather: return "Heather"
        case .waste: return "Waste"
        case .rock: return "Rock"
        case .pineNeedle: return "Pine Needles"
        }
    }

    var friction: Float {
        switch self {
        case .tee: return 0.42
        case .fairway: return 0.38
        case .rough: return 0.72
        case .green: return 0.18
        case .sand: return 0.88
        case .water: return 1.0
        case .heather: return 0.80
        case .waste: return 0.70
        case .rock: return 0.15
        case .pineNeedle: return 0.64
        }
    }

    var restitution: Float {
        switch self {
        case .green: return 0.28
        case .fairway, .tee: return 0.34
        case .rough, .heather, .pineNeedle: return 0.18
        case .sand, .waste: return 0.08
        case .rock: return 0.55
        case .water: return 0
        }
    }
}

enum WeatherCondition: String, Codable, CaseIterable, Identifiable {
    case clear, overcast, windy, rain, goldenHour, fog, coastalBreeze, alpineClear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: return "Clear"
        case .overcast: return "Overcast"
        case .windy: return "Windy"
        case .rain: return "Rain"
        case .goldenHour: return "Golden Hour"
        case .fog: return "Fog"
        case .coastalBreeze: return "Coastal Breeze"
        case .alpineClear: return "Alpine Sun"
        }
    }

    var windMultiplier: Float {
        switch self {
        case .windy: return 1.85
        case .coastalBreeze: return 1.35
        case .rain: return 1.15
        case .fog, .overcast: return 0.7
        default: return 1.0
        }
    }

    var ambientGain: Float {
        switch self {
        case .overcast, .fog, .rain: return 0.72
        case .goldenHour: return 0.9
        default: return 1.0
        }
    }
}

enum CourseID: String, Codable, CaseIterable, Identifiable {
    case pebbleGreens
    case oceanPines
    case desertLinks
    case alpineCrest
    case stAndrewsBay

    var id: String { rawValue }
}

enum Dogleg: String, Codable {
    case none, left, right
}

enum HazardKind: String, Codable, CaseIterable {
    case bunker, water, ocean, trees, rock, cliff, creek, potBunker, waste, wall, lake
}

struct Vec2: Codable, Hashable {
    var x: Float
    var z: Float
}

struct Hazard: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: HazardKind
    var name: String
    var position: Vec2
    var radius: Float
    var severity: Float
}

struct Hole: Identifiable, Codable, Hashable {
    var id: UUID
    var number: Int
    var name: String
    var par: Int
    var yards: Int
    var handicap: Int
    var primaryTerrain: TerrainType
    var elevationChangeYards: Double
    var fairwayWidthYards: Double
    var greenSpeed: Double
    var turfFriction: Float
    var dogleg: Dogleg
    var hazards: [Hazard]
    var windBias: Vec2
    var greenTiering: Float
    var notes: String

    var meters: Double { Double(yards) * 0.9144 }
}

struct Course: Identifiable, Codable, Hashable {
    var id: CourseID
    var name: String
    var subtitle: String
    var location: String
    var par: Int
    var slope: Int
    var rating: Double
    var climate: String
    var defaultWeather: WeatherCondition
    var weatherOptions: [WeatherCondition]
    var holes: [Hole]
    var accentHex: String
    var difficulty: Int

    var totalYards: Int { holes.reduce(0) { $0 + $1.yards } }
    var frontNinePar: Int { holes.prefix(9).reduce(0) { $0 + $1.par } }
    var backNinePar: Int { holes.suffix(9).reduce(0) { $0 + $1.par } }

    var accentColor: Color {
        Color(hex: accentHex)
    }
}

enum CourseCatalog {
    static let all: [Course] = [
        pebbleGreens(),
        oceanPines(),
        desertLinks(),
        alpineCrest(),
        stAndrewsBay()
    ]

    static func course(id: CourseID) -> Course {
        all.first { $0.id == id } ?? all[0]
    }

    static func pebbleGreens() -> Course {
        makeCourse(
            id: .pebbleGreens,
            name: "Pebble Greens",
            subtitle: "Coastal Links",
            location: "Monterey Headlands",
            par: 72,
            slope: 145,
            rating: 75.5,
            climate: "Crisp coastal sunlight, ocean cliffs, white sand",
            defaultWeather: .coastalBreeze,
            weather: [.coastalBreeze, .clear, .windy, .fog],
            accent: "#1B6CA8",
            difficulty: 4,
            pars: Self.par72,
            names: [
                "Cypress Tee", "Seal Rock", "Inlet Carry", "Cliffside", "Otter Cove",
                "Headland", "Spray Point", "Stillwater", "Lone Cypress",
                "Pacific Turn", "Bluff 11", "Ocean Dogleg", "White Sand Ribbon",
                "Tide Gate", "Carmel View", "Sunset 16", "Pebble Reach", "18th Along the Sea"
            ],
            yards: [381, 511, 188, 327, 430, 205, 398, 548, 404, 446, 170, 536, 392, 415, 197, 403, 525, 543],
            style: .coastal
        )
    }

    static func oceanPines() -> Course {
        makeCourse(
            id: .oceanPines,
            name: "Ocean Pines",
            subtitle: "Pacific Northwest Forest",
            location: "Oregon Rainshadow",
            par: 72,
            slope: 139,
            rating: 73.8,
            climate: "Moody overcast forest, wet turf, pine galleries",
            defaultWeather: .overcast,
            weather: [.overcast, .rain, .fog, .clear],
            accent: "#1F4D3A",
            difficulty: 4,
            pars: Self.par72Alt,
            names: [
                "Cathedral Pines", "Needlestrew", "Creek Crossing", "Nurse Log", "Fern Gully",
                "Switchback", "Hemlock Narrows", "Salmon Run", "Moss Terrace",
                "Fog Gallery", "Nurse Creek", "Old Growth", "Raven Ridge",
                "Wetland Edge", "Sitka Drop", "Protected Bowl", "Canopy 17", "Lodge Finale"
            ],
            yards: [394, 540, 176, 412, 387, 198, 365, 561, 418, 429, 162, 528, 401, 376, 211, 390, 544, 416],
            style: .forest
        )
    }

    static func desertLinks() -> Course {
        makeCourse(
            id: .desertLinks,
            name: "Desert Links",
            subtitle: "Canyon Sunset",
            location: "Red Rock Basin",
            par: 71,
            slope: 133,
            rating: 72.4,
            climate: "Golden-hour canyon light, waste bunkers, heat shimmer",
            defaultWeather: .goldenHour,
            weather: [.goldenHour, .clear, .windy],
            accent: "#C45C26",
            difficulty: 3,
            pars: Self.par71,
            names: [
                "Mesa Open", "Saguaro", "Slot Canyon", "Wash Carry", "Red Wall",
                "Heat Shimmer", "Arroyo", "Box Canyon", "Sunset Shelf",
                "Waste Sea", "Needle Eye", "Long Mesa", "Cholla",
                "Rim Shot", "Petroglyph", "Canyon Echo", "Last Light", "Firebowl 18"
            ],
            yards: [430, 165, 408, 552, 391, 188, 444, 419, 375, 461, 534, 149, 402, 388, 176, 518, 412, 401],
            style: .desert
        )
    }

    static func alpineCrest() -> Course {
        makeCourse(
            id: .alpineCrest,
            name: "Alpine Crest",
            subtitle: "Mountain Peaks",
            location: "High Sierra Spine",
            par: 72,
            slope: 148,
            rating: 76.1,
            climate: "Thin air, snow peaks, alpine lakes, severe elevation",
            defaultWeather: .alpineClear,
            weather: [.alpineClear, .clear, .fog, .windy],
            accent: "#4C7CF0",
            difficulty: 5,
            pars: Self.par72,
            names: [
                "Timberline Tee", "Switchback Rise", "Tarn Mirror", "Granite Drop", "Spruce Corridor",
                "Col", "Glacier View", "Uphill 8", "Lake Shelf",
                "False Front", "Krummholz", "Summit Carry", "Boulder Field",
                "Cirque", "Snowline", "Ridge Traverse", "Downmountain", "Crest 18"
            ],
            yards: [368, 498, 201, 340, 415, 178, 388, 530, 392, 421, 155, 508, 377, 404, 192, 389, 551, 410],
            style: .alpine
        )
    }

    static func stAndrewsBay() -> Course {
        makeCourse(
            id: .stAndrewsBay,
            name: "St. Andrews Bay",
            subtitle: "Scottish Highlands",
            location: "North Sea Links",
            par: 73,
            slope: 141,
            rating: 74.9,
            climate: "Heather hills, pot bunkers, grey skies, rolling wind",
            defaultWeather: .overcast,
            weather: [.overcast, .windy, .fog, .rain, .clear],
            accent: "#6B7340",
            difficulty: 5,
            pars: Self.par73,
            names: [
                "Burnside", "Heather Walk", "Eden Swale", "Road Hole Echo", "Pot Field",
                "Blind Dune", "Fescue Sea", "High Out", "Valley of Sin",
                "Stone Dyke", "Principal's Nose", "Hell Bunker", "Loop Turn",
                "Whins", "Cartgate", "Scholar's", "Road Approach", "Home"
            ],
            yards: [376, 533, 412, 461, 178, 548, 394, 429, 355, 408, 165, 529, 387, 441, 560, 194, 418, 495],
            style: .links
        )
    }

    private enum Style { case coastal, forest, desert, alpine, links }

    /// Classic par-72 split (36-36): 4× par-3, 10× par-4, 4× par-5.
    private static let par72: [Int] = [4, 5, 3, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    private static let par72Alt: [Int] = [4, 5, 3, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    /// Par 71 (35-36): 5× par-3, 9× par-4, 4× par-5.
    private static let par71: [Int] = [4, 3, 4, 5, 4, 3, 4, 4, 4, 4, 5, 3, 4, 4, 3, 5, 4, 4]
    /// Par 73 (37-36).
    private static let par73: [Int] = [4, 5, 4, 4, 3, 5, 4, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]

    private static func makeCourse(
        id: CourseID,
        name: String,
        subtitle: String,
        location: String,
        par: Int,
        slope: Int,
        rating: Double,
        climate: String,
        defaultWeather: WeatherCondition,
        weather: [WeatherCondition],
        accent: String,
        difficulty: Int,
        pars: [Int],
        names: [String],
        yards: [Int],
        style: Style
    ) -> Course {
        precondition(pars.count == 18 && names.count == 18 && yards.count == 18)
        let holes = (1...18).map { n in
            generateHole(
                course: id,
                number: n,
                name: names[n - 1],
                par: pars[n - 1],
                yards: yards[n - 1],
                style: style
            )
        }
        return Course(
            id: id,
            name: name,
            subtitle: subtitle,
            location: location,
            par: par,
            slope: slope,
            rating: rating,
            climate: climate,
            defaultWeather: defaultWeather,
            weatherOptions: weather,
            holes: holes,
            accentHex: accent,
            difficulty: difficulty
        )
    }

    private static func generateHole(
        course: CourseID,
        number: Int,
        name: String,
        par: Int,
        yards: Int,
        style: Style
    ) -> Hole {
        let seed = holeSeed(course: course, number: number)
        var rng = SplitMix64(seed: seed)
        let dogleg: Dogleg = {
            if par == 3 { return .none }
            let roll = rng.nextFloat()
            if roll < 0.38 { return .left }
            if roll < 0.72 { return .right }
            return .none
        }()

        let elevation: Double = {
            switch style {
            case .alpine:
                return (par == 3 ? 18 : 28) * (number % 2 == 0 ? -1.4 : 1.6) + rng.nextSigned() * 12
            case .coastal:
                return Double(number > 12 ? -14 : 6) + rng.nextSigned() * 8
            case .desert:
                return rng.nextSigned() * 16
            case .forest:
                return rng.nextSigned() * 10
            case .links:
                return rng.nextSigned() * 7
            }
        }()

        let fairwayWidth: Double = {
            switch style {
            case .forest: return par == 3 ? 22 : 28 + Double(number % 5) * 1.5
            case .links: return 42 + Double(par) * 2
            case .desert: return 48 + Double(par) * 3
            case .coastal: return 34 + Double(par)
            case .alpine: return 30 + Double(par)
            }
        }()

        let greenSpeed: Double = {
            switch style {
            case .coastal: return 11.5
            case .forest: return 10.2
            case .desert: return 12.0
            case .alpine: return 11.0
            case .links: return 10.6
            }
        }() + rng.nextSigned() * 0.4

        let friction: Float = {
            switch style {
            case .forest, .links: return 0.46
            case .desert: return 0.40
            case .alpine: return 0.42
            case .coastal: return 0.39
            }
        }()

        let wind = Vec2(
            x: rng.nextSigned() * windScale(style),
            z: (style == .coastal || style == .links ? 0.35 : 0.1) + rng.nextSigned() * 0.25
        )

        let hazards = generateHazards(style: style, par: par, number: number, rng: &rng)
        let handicap = strokeIndex(number: number)
        let notes = flavorText(style: style, par: par, dogleg: dogleg, elevation: elevation)

        return Hole(
            id: UUID(uuidString: String(format: "A1B2C3D4-E5F6-7890-ABCD-%012d", seed % 1_000_000_000_000)) ?? UUID(),
            number: number,
            name: name,
            par: par,
            yards: yards,
            handicap: handicap,
            primaryTerrain: style == .links ? .heather : .fairway,
            elevationChangeYards: elevation,
            fairwayWidthYards: fairwayWidth,
            greenSpeed: greenSpeed,
            turfFriction: friction,
            dogleg: dogleg,
            hazards: hazards,
            windBias: wind,
            greenTiering: style == .alpine || style == .links ? 0.45 + rng.nextFloat() * 0.4 : 0.15 + rng.nextFloat() * 0.2,
            notes: notes
        )
    }

    private static func generateHazards(style: Style, par: Int, number: Int, rng: inout SplitMix64) -> [Hazard] {
        var list: [Hazard] = []
        func add(_ kind: HazardKind, _ name: String, x: Float, z: Float, r: Float, sev: Float) {
            list.append(Hazard(id: UUID(), kind: kind, name: name, position: Vec2(x: x, z: z), radius: r, severity: sev))
        }

        switch style {
        case .coastal:
            add(.ocean, "Pacific", x: 0.78, z: 0.45, r: 0.42, sev: 1)
            add(.cliff, "Cliff lip", x: 0.70, z: 0.62, r: 0.16, sev: 0.9)
            add(.bunker, "White sand", x: -0.22, z: 0.72, r: 0.10, sev: 0.6)
            if par >= 5 { add(.ocean, "Inlet", x: 0.15, z: 0.38, r: 0.18, sev: 0.85) }
            if number % 4 == 0 { add(.bunker, "Greenside", x: 0.18, z: 0.88, r: 0.08, sev: 0.5) }
        case .forest:
            add(.trees, "Pine wall L", x: -0.55, z: 0.5, r: 0.28, sev: 0.7)
            add(.trees, "Pine wall R", x: 0.55, z: 0.48, r: 0.26, sev: 0.7)
            add(.creek, "Creek", x: 0.02, z: 0.36 + Float(number % 3) * 0.05, r: 0.12, sev: 0.8)
            add(.bunker, "Green bunker", x: -0.16, z: 0.86, r: 0.09, sev: 0.55)
            if par == 5 { add(.water, "Wetland", x: 0.28, z: 0.58, r: 0.14, sev: 0.75) }
        case .desert:
            add(.waste, "Waste left", x: -0.62, z: 0.5, r: 0.34, sev: 0.5)
            add(.waste, "Waste right", x: 0.64, z: 0.55, r: 0.30, sev: 0.5)
            add(.rock, "Red rock", x: rng.nextSigned() * 0.3, z: 0.4, r: 0.12, sev: 0.8)
            add(.bunker, "Gold trap", x: 0.2, z: 0.84, r: 0.11, sev: 0.6)
            if par == 3 { add(.rock, "Canyon wall", x: 0.4, z: 0.5, r: 0.2, sev: 0.7) }
        case .alpine:
            add(.lake, "Tarn", x: 0.32, z: 0.42, r: 0.16, sev: 0.85)
            add(.rock, "Boulder field", x: -0.28, z: 0.6, r: 0.14, sev: 0.7)
            add(.trees, "Spruce", x: -0.5, z: 0.35, r: 0.22, sev: 0.55)
            add(.bunker, "False front", x: 0.0, z: 0.80, r: 0.08, sev: 0.5)
            if number % 2 == 0 { add(.rock, "Drop-off", x: 0.45, z: 0.7, r: 0.12, sev: 0.9) }
        case .links:
            add(.potBunker, "Pot left", x: -0.18, z: 0.55, r: 0.06, sev: 0.85)
            add(.potBunker, "Pot right", x: 0.22, z: 0.6, r: 0.06, sev: 0.85)
            add(.wall, "Stone dyke", x: 0.05, z: 0.78, r: 0.1, sev: 0.6)
            if par >= 4 { add(.potBunker, "Fairway pot", x: rng.nextSigned() * 0.2, z: 0.4, r: 0.055, sev: 0.8) }
            if number == 17 || number == 4 { add(.wall, "Road wall", x: 0.3, z: 0.9, r: 0.12, sev: 0.7) }
            add(.bunker, "Front pot", x: -0.08, z: 0.88, r: 0.07, sev: 0.75)
        }

        if rng.nextFloat() > 0.55 {
            add(.bunker, "Short right", x: 0.26, z: 0.28, r: 0.08, sev: 0.4)
        }
        return list
    }

    private static func windScale(_ style: Style) -> Float {
        switch style {
        case .links, .coastal: return 0.55
        case .desert, .alpine: return 0.4
        case .forest: return 0.18
        }
    }

    private static func strokeIndex(number: Int) -> Int {
        let order = [6, 14, 2, 8, 12, 16, 4, 10, 18, 5, 13, 1, 9, 11, 17, 3, 7, 15]
        return order[number - 1]
    }

    private static func flavorText(style: Style, par: Int, dogleg: Dogleg, elevation: Double) -> String {
        let dog = dogleg == .none ? "straight" : "dogleg \(dogleg.rawValue)"
        let elev = elevation > 8 ? "uphill" : elevation < -8 ? "downhill" : "level"
        let setting: String
        switch style {
        case .coastal: setting = "Cliffside coastal links with ocean on the right."
        case .forest: setting = "Tight tree-lined corridor with wet, dark turf."
        case .desert: setting = "Wide canyon floor with sprawling waste and long shadows."
        case .alpine: setting = "Thin-air mountain hole; elevation heavily affects carry."
        case .links: setting = "Rolling fescue, pot bunkers, and a blind ridge line."
        }
        return "Par \(par), \(dog), \(elev). \(setting)"
    }

    private static func holeSeed(course: CourseID, number: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in course.rawValue.utf8 {
            hash ^= UInt64(b)
            hash &*= 0x100000001b3
        }
        hash ^= UInt64(number) &* 0x9E3779B97F4A7C15
        return hash
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
    mutating func nextSigned() -> Float {
        nextFloat() * 2 - 1
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (30, 120, 60)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
