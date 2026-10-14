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
    
    // 1. Draw Background Squircle
    let inset = size * 0.075
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = size * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Deep Cosmic Midnight to Royal Indigo & Electric Violet gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.11, green: 0.16, blue: 0.38, alpha: 1.0), // Top: Deep Royal Indigo
        CGColor(red: 0.18, green: 0.10, blue: 0.44, alpha: 1.0), // Mid: Violet Purple
        CGColor(red: 0.05, green: 0.07, blue: 0.18, alpha: 1.0)  // Bottom: Obsidian Navy
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.45, 1.0]
    
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
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
    
    // 2. Inner Rim Specular Highlight (Apple Glass Bevel)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(size * 0.016)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28))
    ctx.strokePath()
    ctx.restoreGState()
    
    // Subtle Top Edge Specular Arc
    let topGlowRect = CGRect(x: rect.minX + size * 0.1, y: rect.maxY - size * 0.15, width: rect.width - size * 0.2, height: size * 0.1)
    if let topGlow = CGGradient(colorsSpace: colorSpace, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.22), CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(topGlow, start: CGPoint(x: topGlowRect.midX, y: topGlowRect.maxY), end: CGPoint(x: topGlowRect.midX, y: topGlowRect.minY), options: [])
        ctx.restoreGState()
    }
    
    // 3. Central Emblem: Modern Layered Folder with Magic Sparkles
    // Base Folder Symbol (Soft Luminous Cyan/Azure)
    let folderConfig = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium)
    if let folderSymbol = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?.withSymbolConfiguration(folderConfig) {
        let folderRect = CGRect(
            x: (size - size * 0.54) / 2 - size * 0.02,
            y: (size - size * 0.54) / 2 - size * 0.02,
            width: size * 0.54,
            height: size * 0.54
        )
        
        ctx.saveGState()
        // Deep drop shadow for the folder
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.03),
            blur: size * 0.06,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        )
        
        // Draw folder tinted in modern gradient or azure cyan
        folderSymbol.draw(in: folderRect, from: .zero, operation: .sourceOver, fraction: 0.95)
        ctx.restoreGState()
    }
    
    // 4. Overlaid Radiant Sparkles / Star Burst (Upper Right)
    let sparkleConfig = NSImage.SymbolConfiguration(pointSize: size * 0.38, weight: .bold)
    if let sparkleSymbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(sparkleConfig) {
        let sparkleRect = CGRect(
            x: size * 0.44,
            y: size * 0.42,
            width: size * 0.44,
            height: size * 0.44
        )
        
        ctx.saveGState()
        // Radiant Cyan & Gold Glow
        ctx.setShadow(
            offset: CGSize(width: 0, height: 0),
            blur: size * 0.07,
            color: CGColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.85)
        )
        sparkleSymbol.draw(in: sparkleRect, from: .zero, operation: .sourceOver, fraction: 1.0)
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

print("Generated new iconset at \(iconsetDir.path)")
