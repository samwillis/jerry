import AppKit
import SpriteKit
import ExpeditionCore

/// Renders the real character rig so the icon stays faithful to Jerry's artwork.
@main enum JerryAppIconRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resources = root.appendingPathComponent("OtherSock/Resources", isDirectory: true)
        let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let scene = SKScene(size: .init(width: 1024, height: 1024)); scene.backgroundColor = .clear
        let tilePath = CGPath(roundedRect: .init(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
        let tile = SKShapeNode(path: tilePath)
        tile.fillColor = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1)
        tile.strokeColor = NSColor(calibratedRed: 0.56, green: 0.47, blue: 0.33, alpha: 0.28); tile.lineWidth = 3
        scene.addChild(tile)
        let crop = SKCropNode(); let mask = SKShapeNode(path: tilePath); mask.fillColor = .white; mask.strokeColor = .clear; crop.maskNode = mask; scene.addChild(crop)
        // A quiet paper vignette provides depth without competing with the face.
        let warmBase = SKShapeNode(ellipseIn: .init(x: 30, y: -260, width: 1060, height: 700))
        warmBase.fillColor = NSColor(calibratedRed: 0.73, green: 0.56, blue: 0.32, alpha: 0.07); warmBase.strokeColor = .clear; crop.addChild(warmBase)
        PaintedPart.rasterScale = 32
        let rig = ExplorerRig()
        // The icon has its own tile; omit the desktop-only silhouette shadow.
        for child in rig.children where child is SKCropNode { child.isHidden = true }
        rig.render(delta: 0)
        // Bake the magnification into geometry, including crop masks. Scaling a
        // rig node magnifies SpriteKit's low-resolution stroke/mask caches.
        func enlarge(_ node: SKNode, by scale: CGFloat) {
            node.position = .init(x: node.position.x * scale, y: node.position.y * scale)
            if let sprite = node as? SKSpriteNode { sprite.size = .init(width: sprite.size.width * scale, height: sprite.size.height * scale) }
            if let shape = node as? SKShapeNode {
                var transform = CGAffineTransform(scaleX: scale, y: scale)
                shape.path = shape.path?.copy(using: &transform); shape.lineWidth *= scale
            }
            if let mask = (node as? SKCropNode)?.maskNode { enlarge(mask, by: scale) }
            for child in node.children { enlarge(child, by: scale) }
        }
        enlarge(rig, by: 14); rig.position = .init(x: 512, y: -240); crop.addChild(rig)
        let view = SKView(frame: .init(origin: .zero, size: scene.size)); view.allowsTransparency = true; view.presentScene(scene)
        guard let rendered = view.texture(from: scene)?.cgImage() else { throw NSError(domain: "IconRenderer", code: 1) }
        func export(_ pixels: Int, to url: URL) throws {
            let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high; context.draw(rendered, in: .init(x: 0, y: 0, width: pixels, height: pixels))
            let image = NSBitmapImageRep(cgImage: context.makeImage()!)
            try image.representation(using: .png, properties: [:])!.write(to: url)
        }
        try export(1024, to: resources.appendingPathComponent("AppIcon.png"))
        for size in [16, 32, 128, 256, 512] {
            try export(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            try export(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
    }
}
