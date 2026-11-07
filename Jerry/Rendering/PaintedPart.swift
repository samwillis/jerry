import AppKit
import SpriteKit

@MainActor
enum ExplorerPalette {
    static let jacket = NSColor(calibratedRed: 0.83, green: 0.53, blue: 0.18, alpha: 1)
    static let trousers = NSColor(calibratedRed: 0.27, green: 0.30, blue: 0.32, alpha: 1)
    static let skin = NSColor(calibratedRed: 0.93, green: 0.74, blue: 0.55, alpha: 1)
    static let bag = NSColor(calibratedRed: 0.52, green: 0.38, blue: 0.25, alpha: 1)
    static let hat = NSColor(calibratedRed: 0.16, green: 0.51, blue: 0.49, alpha: 1)
    static let boots = NSColor(calibratedRed: 0.4, green: 0.26, blue: 0.16, alpha: 1)
}

enum ExplorerMaterial: String {
    case cloth, limbCloth, canvas, skin, leather, felt, canopy
}

/// Small, cached, high-resolution material paintings. No textures are regenerated per frame.
@MainActor
final class PaintedPart: SKSpriteNode {
    private let silhouette: CGPath
    var silhouettePath: CGPath {
        // The painted path is authored in its parent's coordinates, while the
        // sprite itself is positioned at the bounds' centre.
        var transform = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
        return silhouette.copy(using: &transform) ?? silhouette
    }
    private let material: ExplorerMaterial
    private let base: NSColor
    private let bounds: CGRect
    private let cacheTag: String
    private static var textures: [String: SKTexture] = [:]
    /// Higher resolution for exported artwork; desktop rendering keeps its usual cache size.
    static var rasterScale: CGFloat = 4

    init(rect: CGRect, radius: CGFloat, color: NSColor, material: ExplorerMaterial) {
        silhouette = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        bounds = rect
        base = color.usingColorSpace(.deviceRGB) ?? color
        self.material = material
        cacheTag = "rect-\(radius)"
        super.init(texture: nil, color: .clear, size: rect.insetBy(dx: -1, dy: -1).size)
        position = CGPoint(x: rect.midX, y: rect.midY)
        setPainted(true)
    }

    init(path: CGPath, color: NSColor, material: ExplorerMaterial, tag: String) {
        silhouette = path
        bounds = path.boundingBoxOfPath
        base = color.usingColorSpace(.deviceRGB) ?? color
        self.material = material
        cacheTag = tag
        super.init(texture: nil, color: .clear, size: bounds.insetBy(dx: -1, dy: -1).size)
        position = CGPoint(x: bounds.midX, y: bounds.midY)
        setPainted(true)
    }

    required init?(coder: NSCoder) { fatalError("Use the material constructors") }

    func setPainted(_ painted: Bool) {
        let key = "\(cacheTag)-\(bounds)-\(base.redComponent)-\(base.greenComponent)-\(base.blueComponent)-\(material.rawValue)-\(painted)-\(Self.rasterScale)"
        if let cached = Self.textures[key] { texture = cached; return }
        let image = paint(painted: painted)
        let result = SKTexture(cgImage: image)
        result.filteringMode = .linear
        Self.textures[key] = result
        texture = result
    }

    private func paint(painted: Bool) -> CGImage {
        let scale = max(1, min(32, Self.rasterScale))
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        var translation = CGAffineTransform(translationX: 1 - bounds.minX, y: 1 - bounds.minY)
        let path = silhouette.copy(using: &translation)!
        let area = CGRect(x: 1, y: 1, width: bounds.width, height: bounds.height)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if painted {
            let light = mixed(base, with: .white, amount: material == .limbCloth ? 0.065 : (material == .skin ? 0.13 : 0.24))
            let shadow = mixed(base, with: NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.09, alpha: 1), amount: material == .limbCloth ? 0.1 : 0.27)
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [shadow.cgColor, base.cgColor, light.cgColor] as CFArray, locations: [0, 0.48, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: area.maxX, y: area.minY), end: CGPoint(x: area.minX, y: area.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            glow(context, at: CGPoint(x: area.minX + area.width * 0.27, y: area.minY + area.height * 0.78), radius: max(area.width, area.height) * 0.65, color: NSColor.white.withAlphaComponent(material == .limbCloth ? 0.025 : 0.13))
            addGrain(context, in: area)
            details(context, in: area)
        } else {
            context.setFillColor(base.cgColor)
            context.fill(area)
        }
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(painted ? mixed(base, with: .black, amount: 0.6).withAlphaComponent(0.9).cgColor : NSColor(calibratedWhite: 0.15, alpha: 1).cgColor)
        context.setLineWidth(painted ? 0.7 : 1)
        context.strokePath()
        return context.makeImage()!
    }

    private func mixed(_ a: NSColor, with b: NSColor, amount: CGFloat) -> NSColor {
        (a.blended(withFraction: amount, of: b) ?? a).usingColorSpace(.deviceRGB) ?? a
    }

    private func glow(_ context: CGContext, at point: CGPoint, radius: CGFloat, color: NSColor) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: max(radius, 0.1), options: [])
    }

    private func addGrain(_ context: CGContext, in area: CGRect) {
        // A fixed seed gives stable fabric grain instead of frame-to-frame noise.
        var seed: UInt64 = 14731
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 32) / CGFloat(UInt32.max)
        }
        let count = Int(area.width * area.height * (material == .skin ? 0.5 : 2.5))
        for _ in 0..<count {
            let x = area.minX + next() * area.width
            let y = area.minY + next() * area.height
            let pale = next() > 0.5
            context.setFillColor((pale ? NSColor.white : NSColor.black).withAlphaComponent(material == .skin ? 0.015 : 0.035).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: 0.13 + next() * 0.13, height: 0.13 + next() * 0.18))
        }
    }

    private func details(_ context: CGContext, in area: CGRect) {
        let w = area.width, h = area.height
        context.saveGState()
        context.translateBy(x: area.minX, y: area.minY)
        context.setLineCap(.round)
        switch material {
        case .skin:
            if w > 15, h > 12 {
                for x in [w * 0.2, w * 0.78] {
                    glow(context, at: CGPoint(x: x, y: h * 0.3), radius: w * 0.24, color: NSColor(calibratedRed: 0.78, green: 0.3, blue: 0.22, alpha: 0.17))
                }
                let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [NSColor.brown.withAlphaComponent(0.2).cgColor, NSColor.brown.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                context.drawLinearGradient(shade, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h - 5), options: [])
            }
        case .canvas:
            context.setStrokeColor(mixed(base, with: .black, amount: 0.4).withAlphaComponent(0.08).cgColor)
            context.setLineWidth(0.15)
            for x in stride(from: CGFloat(0), through: w, by: 1.4) {
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: h))
            }
            for y in stride(from: CGFloat(0), through: h, by: 1.4) {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: w, y: y))
            }
            context.strokePath()
            let flap = CGPath(roundedRect: CGRect(x: 1.2, y: h * 0.63, width: max(1, w - 2.4), height: h * 0.23), cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(flap)
            context.setFillColor(mixed(base, with: .white, amount: 0.08).cgColor)
            context.fillPath()
            line(context, from: CGPoint(x: 1.5, y: h * 0.63), to: CGPoint(x: w - 1.5, y: h * 0.63), color: .black.withAlphaComponent(0.16), width: 0.45)
            context.setFillColor(NSColor(calibratedRed: 0.64, green: 0.47, blue: 0.25, alpha: 1).cgColor)
            context.fill(CGRect(x: w * 0.5 - 1, y: h * 0.57, width: 2, height: 2.5))
        case .leather:
            glow(context, at: CGPoint(x: w * 0.72, y: h * 0.6), radius: w * 0.6, color: NSColor(calibratedRed: 1, green: 0.86, blue: 0.64, alpha: 0.2))
            line(context, from: CGPoint(x: 0, y: 0.45), to: CGPoint(x: w, y: 0.45), color: .black.withAlphaComponent(0.3), width: 0.75)
        case .felt:
            line(context, from: CGPoint(x: 1, y: h * 0.25), to: CGPoint(x: w - 1, y: h * 0.25), color: mixed(base, with: .black, amount: 0.35).withAlphaComponent(0.5), width: h > 5 ? 1.7 : 0.45)
        case .limbCloth:
            break
        case .cloth:
            line(context, from: CGPoint(x: w * 0.12, y: h * 0.16), to: CGPoint(x: w * 0.6, y: h * 0.23), color: .black.withAlphaComponent(material == .limbCloth ? 0.08 : 0.12), width: 0.4)
            line(context, from: CGPoint(x: w * 0.35, y: h * 0.32), to: CGPoint(x: w * 0.85, y: h * 0.26), color: .white.withAlphaComponent(material == .limbCloth ? 0.045 : 0.11), width: 0.35)
            if w > 15 {
                line(context, from: CGPoint(x: w * 0.53, y: 2), to: CGPoint(x: w * 0.53, y: h - 2), color: .black.withAlphaComponent(0.1), width: 0.3)
                line(context, from: CGPoint(x: w * 0.68, y: h * 0.39), to: CGPoint(x: w * 0.9, y: h * 0.39), color: .black.withAlphaComponent(0.16), width: 0.45)
            }
        case .canopy:
            for x in [w * 0.33, w * 0.67] {
                line(context, from: CGPoint(x: x, y: 0), to: CGPoint(x: w * 0.5, y: h), color: .white.withAlphaComponent(0.12), width: 0.6)
            }
        }
        context.restoreGState()
    }

    private func line(_ context: CGContext, from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: start); context.addLine(to: end); context.strokePath()
    }
}
