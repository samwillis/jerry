import AppKit
import ExpeditionCore

@main enum JOLBrandRenderer {
    @MainActor static func main() throws {
        let (silhouette, eyes) = ExplorerRig.runningBrandArtwork()
        let bounds = silhouette.boundingBoxOfPath
        let scale = 65 / bounds.height
        var transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: -scale,
            tx: 65 - bounds.midX * scale, ty: 75 + bounds.minY * scale
        )
        let runner = svgPath(silhouette.copy(using: &transform)!)
        let expression = svgPath(eyes.copy(using: &transform)!)
        let logo = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 248 84" role="img" aria-labelledby="title">
          <title id="title">JOL — Jerry On Line</title>
          <path d="M40 7Q42 4 44 7L81 68Q83 72 78 72H6Q2 72 4 68Z"
                fill="#3257c7" stroke="#f8f3e0" stroke-width="2.6" stroke-linejoin="round"/>
          <path d="M57 35C48 25 34 27 26 36C18 45 24 55 34 53C42 51 46 44 48 39"
                fill="none" stroke="#f8f3e0" stroke-width="4" stroke-linecap="round"/>
          <path d="\(runner)" fill="#ffda27" stroke="#172947" stroke-width="2.8" stroke-linejoin="round"/>
          <path d="\(expression)" fill="#172947"/>
          <g fill="#f8f3e0" transform="translate(11 0) skewX(-10)">
            <path d="M110 18H145V48C145 62 138 68 123 68H116C102 68 96 62 96 49V45H109V49C109 54 112 56 117 56H123C130 56 132 53 132 48V30H110Z"/>
            <path fill-rule="evenodd" d="M176 17C193 17 203 26 203 42C203 59 193 69 176 69C159 69 149 59 149 42C149 26 159 17 176 17ZM176 30C167 30 162 34 162 42C162 51 167 56 176 56C185 56 190 51 190 42C190 34 185 30 176 30Z"/>
            <path d="M210 18H224V55H245V68H210Z"/>
          </g>
        </svg>
        """
        try logo.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: .utf8)
    }

    private static func svgPath(_ path: CGPath) -> String {
        func point(_ value: CGPoint) -> String {
            String(format: "%.2f %.2f", locale: Locale(identifier: "en_US_POSIX"), value.x, value.y)
        }
        var commands: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: commands.append("M" + point(points[0]))
            case .addLineToPoint: commands.append("L" + point(points[0]))
            case .addQuadCurveToPoint: commands.append("Q" + point(points[0]) + " " + point(points[1]))
            case .addCurveToPoint: commands.append("C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2]))
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined()
    }
}
