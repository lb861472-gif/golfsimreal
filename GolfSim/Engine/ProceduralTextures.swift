import UIKit
import SceneKit

enum ProceduralTextures {
    static func image(size: Int, _ draw: (CGContext, CGFloat) -> Void) -> UIImage {
        let s = CGFloat(size)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        return renderer.image { ctx in
            draw(ctx.cgContext, s)
        }
    }

    static func cgImage(_ ui: UIImage) -> CGImage {
        ui.cgImage ?? UIGraphicsImageRenderer(size: ui.size).image { _ in }.cgImage!
    }

    static func fairway(size: Int = 512, stripe: Bool = true) -> UIImage {
        image(size: size) { ctx, s in
            let base = UIColor(red: 0.18, green: 0.52, blue: 0.22, alpha: 1)
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            for y in stride(from: 0, to: Int(s), by: 1) {
                let n = fbm(Float(y) * 0.03, 3.1, octaves: 3)
                let shade = 0.04 * CGFloat(n)
                ctx.setFillColor(UIColor(red: 0.16 + shade, green: 0.50 + shade, blue: 0.20, alpha: 0.35).cgColor)
                ctx.fill(CGRect(x: 0, y: CGFloat(y), width: s, height: 1))
            }
            if stripe {
                let band = s / 14
                for i in 0..<14 {
                    if i % 2 == 0 {
                        ctx.setFillColor(UIColor(white: 1, alpha: 0.07).cgColor)
                        ctx.fill(CGRect(x: 0, y: CGFloat(i) * band, width: s, height: band))
                    }
                }
            }
            sprinkle(ctx, s, color: UIColor(red: 0.12, green: 0.38, blue: 0.14, alpha: 0.4), count: 900)
        }
    }

    static func green(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            for y in 0..<Int(s) {
                for x in 0..<Int(s) where x % 2 == 0 {
                    let n = fbm(Float(x) * 0.04, Float(y) * 0.04, octaves: 4)
                    let g = 0.42 + 0.12 * CGFloat(n)
                    ctx.setFillColor(UIColor(red: 0.10, green: g, blue: 0.22, alpha: 1).cgColor)
                    ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 2, height: 1))
                }
            }
        }
    }

    static func rough(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.22, green: 0.40, blue: 0.12, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            sprinkle(ctx, s, color: UIColor(red: 0.30, green: 0.46, blue: 0.10, alpha: 0.7), count: 2400)
            sprinkle(ctx, s, color: UIColor(red: 0.18, green: 0.28, blue: 0.08, alpha: 0.6), count: 1600)
        }
    }

    static func sand(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.86, green: 0.78, blue: 0.55, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            sprinkle(ctx, s, color: UIColor(red: 0.72, green: 0.62, blue: 0.40, alpha: 0.55), count: 3200)
            sprinkle(ctx, s, color: UIColor(white: 1, alpha: 0.18), count: 800)
        }
    }

    static func desertSand(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.78, green: 0.55, blue: 0.28, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            sprinkle(ctx, s, color: UIColor(red: 0.62, green: 0.38, blue: 0.18, alpha: 0.5), count: 2800)
        }
    }

    static func heather(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.42, green: 0.40, blue: 0.18, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            sprinkle(ctx, s, color: UIColor(red: 0.45, green: 0.28, blue: 0.38, alpha: 0.45), count: 1800)
            sprinkle(ctx, s, color: UIColor(red: 0.55, green: 0.50, blue: 0.22, alpha: 0.4), count: 1200)
        }
    }

    static func rock(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.38, green: 0.22, blue: 0.16, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            sprinkle(ctx, s, color: UIColor(red: 0.55, green: 0.32, blue: 0.20, alpha: 0.5), count: 1400)
        }
    }

    static func pineNeedle(size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.18, green: 0.22, blue: 0.10, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.setStrokeColor(UIColor(red: 0.28, green: 0.32, blue: 0.12, alpha: 0.7).cgColor)
            ctx.setLineWidth(1)
            for _ in 0..<700 {
                let x = CGFloat.random(in: 0...s)
                let y = CGFloat.random(in: 0...s)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -6...6), y: y + CGFloat.random(in: 4...10)))
                ctx.strokePath()
            }
        }
    }

    static func ballAlbedo(size: Int = 256) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.setStrokeColor(UIColor(white: 0.78, alpha: 0.7).cgColor)
            ctx.setLineWidth(1)
            let cols = 18
            let rows = 10
            for r in 0..<rows {
                for c in 0..<cols {
                    let ox = r % 2 == 0 ? 0.0 : 0.5
                    let x = (CGFloat(c) + ox) / CGFloat(cols) * s
                    let y = CGFloat(r) / CGFloat(rows) * s
                    ctx.strokeEllipse(in: CGRect(x: x, y: y, width: s / 22, height: s / 22))
                }
            }
        }
    }

    static func ballNormal(size: Int = 256) -> UIImage {
        image(size: size) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            let cols = 18
            let rows = 10
            for r in 0..<rows {
                for c in 0..<cols {
                    let ox = r % 2 == 0 ? 0.0 : 0.5
                    let x = (CGFloat(c) + ox) / CGFloat(cols) * s
                    let y = CGFloat(r) / CGFloat(rows) * s
                    let rect = CGRect(x: x, y: y, width: s / 20, height: s / 20)
                    ctx.setFillColor(UIColor(red: 0.42, green: 0.42, blue: 0.92, alpha: 1).cgColor)
                    ctx.fillEllipse(in: rect)
                    ctx.setFillColor(UIColor(red: 0.62, green: 0.62, blue: 1, alpha: 0.7).cgColor)
                    ctx.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
                }
            }
        }
    }

    static func waterNormal(size: Int = 256, phase: CGFloat) -> UIImage {
        image(size: size) { ctx, s in
            for y in 0..<Int(s) {
                for x in stride(from: 0, to: Int(s), by: 2) {
                    let u = Float(x) / Float(s)
                    let v = Float(y) / Float(s)
                    let w = sinf(u * 22 + Float(phase) * 4) + sinf(v * 18 - Float(phase) * 3.2)
                    let nx = 0.5 + 0.25 * CGFloat(w)
                    let ny = 0.5 + 0.25 * CGFloat(cosf(u * 14 + v * 10 + Float(phase)))
                    ctx.setFillColor(UIColor(red: nx, green: ny, blue: 1, alpha: 1).cgColor)
                    ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 2, height: 1))
                }
            }
        }
    }

    static func skyGradient(top: UIColor, horizon: UIColor, bottom: UIColor, size: Int = 512) -> UIImage {
        image(size: size) { ctx, s in
            let colors = [top.cgColor, horizon.cgColor, bottom.cgColor] as CFArray
            let locs: [CGFloat] = [0, 0.52, 1]
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: 0), end: CGPoint(x: s / 2, y: s), options: [])
            }
        }
    }

    static func material(
        albedo: UIImage,
        roughness: CGFloat,
        metalness: CGFloat = 0,
        normal: UIImage? = nil,
        shininess: CGFloat = 0.2
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = albedo
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        m.normal.contents = normal
        m.specular.contents = UIColor.white
        m.shininess = shininess
        m.locksAmbientWithDiffuse = true
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        return m
    }

    private static func sprinkle(_ ctx: CGContext, _ s: CGFloat, color: UIColor, count: Int) {
        ctx.setFillColor(color.cgColor)
        for _ in 0..<count {
            let x = CGFloat.random(in: 0...s)
            let y = CGFloat.random(in: 0...s)
            let r = CGFloat.random(in: 0.6...2.2)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
    }

    static func fbm(_ x: Float, _ y: Float, octaves: Int) -> Float {
        var amp: Float = 0.5
        var freq: Float = 1
        var sum: Float = 0
        for _ in 0..<octaves {
            sum += amp * noise(x * freq, y * freq)
            freq *= 2
            amp *= 0.5
        }
        return sum
    }

    static func noise(_ x: Float, _ y: Float) -> Float {
        let ix = floorf(x)
        let iy = floorf(y)
        let fx = x - ix
        let fy = y - iy
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy)
        let b = hash(ix + 1, iy)
        let c = hash(ix, iy + 1)
        let d = hash(ix + 1, iy + 1)
        let ab = a + (b - a) * ux
        let cd = c + (d - c) * ux
        return ab + (cd - ab) * uy
    }

    static func hash(_ x: Float, _ y: Float) -> Float {
        var s = sinf(x * 127.1 + y * 311.7) * 43758.5453
        s = s - floorf(s)
        return s * 2 - 1
    }
}
