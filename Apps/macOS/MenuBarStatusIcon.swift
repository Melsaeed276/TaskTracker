import AppKit
import SwiftUI

/// The app icon's four foreground vectors as an `NSImage` template for the macOS menu bar.
/// Keep these coordinates aligned with `Design/AppIcon/Source/`.
///
/// `MenuBarExtra` labels need a real template `NSImage`/`Image` — a SwiftUI `Canvas` often
/// renders blank in the status item (app is running, CloudKit syncs, but the bar looks empty).
enum MenuBarStatusIcon {
    static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.saveGState()
            defer { context.restoreGState() }

            let scale = rect.width / 1024
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            // AppKit drawing is flipped vs SwiftUI Path coords used by the icon source.
            context.translateBy(x: 0, y: 1024)
            context.scaleBy(x: 1, y: -1)

            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            context.addPath(crownPath.cgPath)
            context.fillPath()

            context.addPath(ringPath.cgPath)
            context.setLineWidth(76)
            context.setLineCap(.round)
            context.strokePath()

            context.addPath(markersPath.cgPath)
            context.fillPath()

            context.addPath(checkmarkPath.cgPath)
            context.setLineWidth(78)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }()

    private static var crownPath: Path {
        Path(roundedRect: CGRect(x: 430, y: 122, width: 164, height: 88), cornerRadius: 39)
    }

    private static var ringPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 512, y: 205))
        path.addCurve(
            to: CGPoint(x: 207, y: 510),
            control1: CGPoint(x: 343.6, y: 205),
            control2: CGPoint(x: 207, y: 341.6)
        )
        path.addCurve(
            to: CGPoint(x: 512, y: 815),
            control1: CGPoint(x: 207, y: 678.4),
            control2: CGPoint(x: 343.6, y: 815)
        )
        path.addCurve(
            to: CGPoint(x: 817, y: 510),
            control1: CGPoint(x: 680.4, y: 815),
            control2: CGPoint(x: 817, y: 678.4)
        )
        path.addCurve(
            to: CGPoint(x: 721, y: 288),
            control1: CGPoint(x: 817, y: 422.5),
            control2: CGPoint(x: 780.1, y: 343.6)
        )
        return path
    }

    private static var markersPath: Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 490, y: 272, width: 44, height: 76), cornerSize: CGSize(width: 22, height: 22))
        path.addRoundedRect(in: CGRect(x: 676, y: 488, width: 76, height: 44), cornerSize: CGSize(width: 22, height: 22))
        path.addRoundedRect(in: CGRect(x: 490, y: 676, width: 44, height: 76), cornerSize: CGSize(width: 22, height: 22))
        path.addRoundedRect(in: CGRect(x: 272, y: 488, width: 76, height: 44), cornerSize: CGSize(width: 22, height: 22))
        return path
    }

    private static var checkmarkPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 373, y: 505))
        path.addLine(to: CGPoint(x: 471, y: 603))
        path.addLine(to: CGPoint(x: 664, y: 393))
        return path
    }
}
