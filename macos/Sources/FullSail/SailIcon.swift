import AppKit

enum SailIcon {
    static let green = NSColor(srgbRed: 0.12, green: 0.76, blue: 0.65, alpha: 1)
    static let forest = NSColor(srgbRed: 0.19, green: 0.38, blue: 0.35, alpha: 1)
    static let yellow = NSColor(srgbRed: 0.99, green: 0.93, blue: 0.57, alpha: 1)

    static func polygon(_ points: [NSPoint], color: NSColor) {
        let p = NSBezierPath()
        p.move(to: points[0])
        for point in points.dropFirst() { p.line(to: point) }
        p.close(); color.setFill(); p.fill()
    }
    // Coordinates follow the original three-triangle Wholesail mark.
    static func draw(in rect: NSRect, raised: Bool, template: Bool, ink: NSColor = .black) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 24, yBy: rect.height / 24)
        transform.concat()
        polygon([.init(x: 2, y: 7), .init(x: 12.1, y: 2), .init(x: 22, y: 7)],
                color: template ? ink : yellow)
        if raised {
            polygon([.init(x: 2, y: 8.7), .init(x: 11.3, y: 22), .init(x: 11.3, y: 8.7)],
                    color: template ? ink : forest)
            polygon([.init(x: 12.7, y: 22), .init(x: 22, y: 8.7), .init(x: 12.7, y: 8.7)],
                    color: template ? ink : green)
        } else {
            // Same hull and full-height mast, with both sails furled on the boom.
            let mast = NSBezierPath(roundedRect: .init(x: 11.25, y: 9, width: 1.5, height: 13),
                                    xRadius: 0.75, yRadius: 0.75)
            (template ? ink : forest).setFill(); mast.fill()
            polygon([.init(x: 3, y: 8.7), .init(x: 6, y: 11.7), .init(x: 10.5, y: 10),
                     .init(x: 10.5, y: 8.7)], color: template ? ink : forest)
            polygon([.init(x: 13.5, y: 8.7), .init(x: 13.5, y: 10), .init(x: 18, y: 11.7),
                     .init(x: 21, y: 8.7)], color: template ? ink : green)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func image(raised: Bool, size: CGFloat = 22, template: Bool = true) -> NSImage {
        let image = NSImage(size: .init(width: size, height: size), flipped: false) { rect in
            draw(in: rect, raised: raised, template: template); return true
        }
        image.isTemplate = template
        return image
    }
    static func png(_ image: NSImage, to url: URL) throws {
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    static func export(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for raised in [true, false] {
            try png(image(raised: raised, size: 256, template: false),
                    to: folder.appendingPathComponent(raised ? "sails-up.png" : "sails-down.png"))
        }
        let icon = NSImage(size: .init(width: 1024, height: 1024), flipped: false) { rect in
            NSColor(srgbRed: 0.07, green: 0.19, blue: 0.18, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 220, yRadius: 220).fill()
            draw(in: rect.insetBy(dx: 170, dy: 160), raised: true, template: false)
            return true
        }
        let set = folder.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(size * scale)
                let resized = NSImage(size: .init(width: pixels, height: pixels), flipped: false) { rect in
                    icon.draw(in: rect); return true
                }
                try png(resized, to: set.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
            }
        }
        let preview = NSImage(size: .init(width: 1200, height: 660), flipped: false) { rect in
            NSColor(srgbRed: 0.96, green: 0.97, blue: 0.95, alpha: 1).setFill()
            rect.fill()
            func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ bold: Bool = false) {
                string.draw(at: .init(x: x, y: y), withAttributes: [
                    .font: bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size),
                    .foregroundColor: forest
                ])
            }
            text("Full Sail", 70, 555, 46, true)
            text("A little Wholesail wind for your Mac.", 70, 510, 23)
            for (index, raised) in [true, false].enumerated() {
                let x = CGFloat(index) * 555 + 70
                NSColor.white.setFill()
                NSBezierPath(roundedRect: .init(x: x, y: 130, width: 505, height: 330), xRadius: 24, yRadius: 24).fill()
                draw(in: .init(x: x + 40, y: 230, width: 170, height: 170), raised: raised, template: false)
                text(raised ? "Sails up" : "Sails down", x + 245, 335, 28, true)
                text(raised ? "Keep awake" : "Normal sleep", x + 245, 300, 20)
                text("MENU BAR", x + 40, 180, 12, true)
                for (offset, dark) in [false, true].enumerated() {
                    let bar = NSRect(x: x + 155 + CGFloat(offset) * 145, y: 165, width: 120, height: 40)
                    (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                    NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
                    let drawing = NSRect(x: bar.midX - 25, y: bar.midY - 11, width: 22, height: 22)
                    draw(in: drawing, raised: raised, template: true, ink: dark ? .white : .black)
                    (raised ? "☕" : "🛌").draw(at: .init(x: bar.midX + 1, y: bar.midY - 11),
                                              withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
                }
            }
            text("Native menu bar app  ·  No Dock icon  ·  Timed sessions  ·  Thermal protection", 70, 65, 19)
            return true
        }
        try png(preview, to: folder.appendingPathComponent("icon-preview.png"))
    }
}
