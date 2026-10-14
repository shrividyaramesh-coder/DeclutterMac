#!/usr/bin/env swift
import Cocoa
import CoreGraphics

func createIconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    // Draw background squircle
    let inset = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Background gradient: Vibrant Deep Blue to Teal / Cyan
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.12, green: 0.23, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.05, green: 0.65, blue: 0.92, alpha: 1.0)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
        ctx.restoreGState()
    }
    
    // Subtle inner border
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(size * 0.015)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35))
    ctx.strokePath()
    ctx.restoreGState()
    
    // Draw Sparkles Symbol
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold)
    if let sfSymbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolRect = CGRect(
            x: (size - size * 0.5) / 2,
            y: (size - size * 0.5) / 2,
            width: size * 0.5,
            height: size * 0.5
        )
        
        // Render in pure white with subtle drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
        sfSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()
    }
    
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, at url: URL, pixelSize: Int) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: url)
    }
}

// Generate iconset directory
let fileManager = FileManager.default
let iconsetDir = URL(fileURLWithPath: "build/icon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try! fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, points: CGFloat, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for item in sizes {
    let px = Int(item.points * CGFloat(item.scale))
    let img = createIconImage(size: CGFloat(px))
    let targetURL = iconsetDir.appendingPathComponent(item.name)
    savePNG(image: img, at: targetURL, pixelSize: px)
}

print("Generated iconset at \(iconsetDir.path)")
