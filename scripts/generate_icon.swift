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
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // 1. Background Squircle
    let inset = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = size * 0.225
    let squirclePath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Rich Deep Midnight / Space Blue gradient with smooth ambient lighting
    let bgColors = [
        CGColor(red: 0.08, green: 0.12, blue: 0.24, alpha: 1.0),
        CGColor(red: 0.03, green: 0.05, blue: 0.13, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        
        // Ambient Inner Glow
        let innerGlowColors = [
            CGColor(red: 0.14, green: 0.45, blue: 0.95, alpha: 0.32),
            CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ] as CFArray
        if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: innerGlowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: rect.midX, y: rect.midY + size * 0.06), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.65, options: [])
        }
        ctx.restoreGState()
    }
    
    // Inner Rim Highlight (Apple Glass Bevel)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.016)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.strokePath()
    ctx.restoreGState()
    
    // 2. Folder Dimensions
    let fWidth = size * 0.66
    let fHeight = size * 0.48
    let fX = (size - fWidth) / 2
    let fY = (size - fHeight) / 2 - size * 0.035
    
    // Folder Back Flap
    let backRect = CGRect(x: fX, y: fY, width: fWidth, height: fHeight)
    let backPath = CGMutablePath()
    let br: CGFloat = size * 0.045
    let tabW = fWidth * 0.40
    let tabH = size * 0.05
    
    backPath.move(to: CGPoint(x: backRect.minX + br, y: backRect.minY))
    backPath.addArc(tangent1End: CGPoint(x: backRect.maxX, y: backRect.minY), tangent2End: CGPoint(x: backRect.maxX, y: backRect.maxY), radius: br)
    backPath.addArc(tangent1End: CGPoint(x: backRect.maxX, y: backRect.maxY), tangent2End: CGPoint(x: backRect.minX, y: backRect.maxY), radius: br)
    backPath.addLine(to: CGPoint(x: backRect.minX + tabW + size * 0.03, y: backRect.maxY))
    backPath.addCurve(to: CGPoint(x: backRect.minX + tabW, y: backRect.maxY + tabH), control1: CGPoint(x: backRect.minX + tabW + size * 0.015, y: backRect.maxY), control2: CGPoint(x: backRect.minX + tabW + size * 0.005, y: backRect.maxY + tabH))
    backPath.addLine(to: CGPoint(x: backRect.minX + br, y: backRect.maxY + tabH))
    backPath.addArc(tangent1End: CGPoint(x: backRect.minX, y: backRect.maxY + tabH), tangent2End: CGPoint(x: backRect.minX, y: backRect.minY), radius: br)
    backPath.addArc(tangent1End: CGPoint(x: backRect.minX, y: backRect.minY), tangent2End: CGPoint(x: backRect.maxX, y: backRect.minY), radius: br)
    backPath.closeSubpath()
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.06, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    let backColors = [
        CGColor(red: 0.07, green: 0.38, blue: 0.82, alpha: 1.0),
        CGColor(red: 0.03, green: 0.24, blue: 0.62, alpha: 1.0)
    ] as CFArray
    if let backGrad = CGGradient(colorsSpace: colorSpace, colors: backColors, locations: [0.0, 1.0]) {
        ctx.addPath(backPath)
        ctx.clip()
        ctx.drawLinearGradient(backGrad, start: CGPoint(x: backRect.midX, y: backRect.maxY + tabH), end: CGPoint(x: backRect.midX, y: backRect.minY), options: [])
    }
    ctx.restoreGState()
    
    // 3. Three Neatly Organized File Cards Emerging from Folder
    struct FileCard {
        let xOffset: CGFloat
        let yOffset: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let topColor: CGColor
        let botColor: CGColor
        let accentColor: CGColor
    }
    let cards: [FileCard] = [
        // Left Card (Purple / Documents & Apps)
        FileCard(
            xOffset: -size * 0.15, yOffset: size * 0.09,
            width: size * 0.27, height: size * 0.33, angle: -0.09,
            topColor: CGColor(red: 0.60, green: 0.42, blue: 1.0, alpha: 1.0),
            botColor: CGColor(red: 0.38, green: 0.22, blue: 0.88, alpha: 1.0),
            accentColor: CGColor(red: 0.82, green: 0.72, blue: 1.0, alpha: 0.7)
        ),
        // Right Card (Emerald Mint / Clean Reclaimed Storage)
        FileCard(
            xOffset: size * 0.15, yOffset: size * 0.09,
            width: size * 0.27, height: size * 0.33, angle: 0.09,
            topColor: CGColor(red: 0.18, green: 0.86, blue: 0.60, alpha: 1.0),
            botColor: CGColor(red: 0.05, green: 0.62, blue: 0.44, alpha: 1.0),
            accentColor: CGColor(red: 0.68, green: 1.0, blue: 0.85, alpha: 0.7)
        ),
        // Center Card (Vibrant Electric Azure / Media & Files)
        FileCard(
            xOffset: 0.0, yOffset: size * 0.13,
            width: size * 0.29, height: size * 0.35, angle: 0.0,
            topColor: CGColor(red: 0.28, green: 0.78, blue: 1.0, alpha: 1.0),
            botColor: CGColor(red: 0.08, green: 0.52, blue: 0.98, alpha: 1.0),
            accentColor: CGColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 0.85)
        )
    ]
    for c in cards {
        ctx.saveGState()
        ctx.translateBy(x: size * 0.5 + c.xOffset, y: fY + size * 0.15 + c.yOffset)
        ctx.rotate(by: c.angle)
        
        let cRect = CGRect(x: -c.width / 2, y: -c.height / 2, width: c.width, height: c.height)
        let cPath = CGPath(roundedRect: cRect, cornerWidth: size * 0.026, cornerHeight: size * 0.026, transform: nil)
        
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.045, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        
        let gradColors = [c.topColor, c.botColor] as CFArray
        if let cGrad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.addPath(cPath)
            ctx.clip()
            ctx.drawLinearGradient(cGrad, start: CGPoint(x: 0, y: cRect.maxY), end: CGPoint(x: 0, y: cRect.minY), options: [])
            
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
            ctx.setLineWidth(size * 0.007)
            ctx.strokeLineSegments(between: [CGPoint(x: cRect.minX + size * 0.02, y: cRect.maxY - size * 0.008), CGPoint(x: cRect.maxX - size * 0.02, y: cRect.maxY - size * 0.008)])
            
            ctx.setStrokeColor(c.accentColor)
            ctx.setLineWidth(size * 0.012)
            ctx.setLineCap(.round)
            
            let l1 = cRect.maxY - size * 0.045
            ctx.strokeLineSegments(between: [CGPoint(x: cRect.minX + size * 0.035, y: l1), CGPoint(x: cRect.maxX - size * 0.08, y: l1)])
            let l2 = cRect.maxY - size * 0.075
            ctx.strokeLineSegments(between: [CGPoint(x: cRect.minX + size * 0.035, y: l2), CGPoint(x: cRect.maxX - size * 0.035, y: l2)])
            let l3 = cRect.maxY - size * 0.105
            ctx.strokeLineSegments(between: [CGPoint(x: cRect.minX + size * 0.035, y: l3), CGPoint(x: cRect.midX + size * 0.02, y: l3)])
        }
        ctx.restoreGState()
    }
    
    // 4. Folder Front Pocket (Sculpted with a gentle curved top notch)
    let frontH = fHeight * 0.72
    let frontRect = CGRect(x: fX, y: fY, width: fWidth, height: frontH)
    let frontPath = CGMutablePath()
    let fbr: CGFloat = size * 0.05
    
    frontPath.move(to: CGPoint(x: frontRect.minX + fbr, y: frontRect.minY))
    frontPath.addArc(tangent1End: CGPoint(x: frontRect.maxX, y: frontRect.minY), tangent2End: CGPoint(x: frontRect.maxX, y: frontRect.maxY), radius: fbr)
    frontPath.addArc(tangent1End: CGPoint(x: frontRect.maxX, y: frontRect.maxY), tangent2End: CGPoint(x: frontRect.midX, y: frontRect.maxY), radius: fbr * 0.6)
    
    // Gentle concave lip in the center
    frontPath.addCurve(
        to: CGPoint(x: frontRect.minX + fbr * 0.6, y: frontRect.maxY),
        control1: CGPoint(x: frontRect.midX + size * 0.06, y: frontRect.maxY - size * 0.012),
        control2: CGPoint(x: frontRect.midX - size * 0.06, y: frontRect.maxY - size * 0.012)
    )
    frontPath.addArc(tangent1End: CGPoint(x: frontRect.minX, y: frontRect.maxY), tangent2End: CGPoint(x: frontRect.minX, y: frontRect.minY), radius: fbr * 0.6)
    frontPath.addArc(tangent1End: CGPoint(x: frontRect.minX, y: frontRect.minY), tangent2End: CGPoint(x: frontRect.maxX, y: frontRect.minY), radius: fbr)
    frontPath.closeSubpath()
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.07, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
    
    let frontColors = [
        CGColor(red: 0.22, green: 0.68, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.06, green: 0.44, blue: 0.92, alpha: 1.0),
        CGColor(red: 0.02, green: 0.30, blue: 0.78, alpha: 1.0)
    ] as CFArray
    if let frontGrad = CGGradient(colorsSpace: colorSpace, colors: frontColors, locations: [0.0, 0.45, 1.0]) {
        ctx.addPath(frontPath)
        ctx.clip()
        ctx.drawLinearGradient(frontGrad, start: CGPoint(x: frontRect.midX, y: frontRect.maxY), end: CGPoint(x: frontRect.midX, y: frontRect.minY), options: [])
        
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.setLineWidth(size * 0.012)
        ctx.addPath(frontPath)
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // 5. Floating Emerald Mint Verified Checkmark Badge in Bottom Right
    let bSize = size * 0.22
    let bCenter = CGPoint(x: fX + fWidth - bSize * 0.55, y: fY + bSize * 0.5)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: CGColor(red: 0.05, green: 0.6, blue: 0.35, alpha: 0.6))
    
    let sealColors = [
        CGColor(red: 0.25, green: 0.92, blue: 0.65, alpha: 1.0),
        CGColor(red: 0.06, green: 0.68, blue: 0.44, alpha: 1.0)
    ] as CFArray
    let bRect = CGRect(x: bCenter.x - bSize/2, y: bCenter.y - bSize/2, width: bSize, height: bSize)
    let bCircle = CGPath(ellipseIn: bRect, transform: nil)
    
    if let sGrad = CGGradient(colorsSpace: colorSpace, colors: sealColors, locations: [0.0, 1.0]) {
        ctx.addPath(bCircle)
        ctx.clip()
        ctx.drawLinearGradient(sGrad, start: CGPoint(x: bCenter.x, y: bRect.maxY), end: CGPoint(x: bCenter.x, y: bRect.minY), options: [])
        
        // Specular rim
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
        ctx.setLineWidth(size * 0.01)
        ctx.addPath(bCircle)
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // Bold White Checkmark in badge
    ctx.saveGState()
    let check = CGMutablePath()
    check.move(to: CGPoint(x: bCenter.x - bSize * 0.22, y: bCenter.y))
    check.addLine(to: CGPoint(x: bCenter.x - bSize * 0.05, y: bCenter.y - bSize * 0.18))
    check.addLine(to: CGPoint(x: bCenter.x + bSize * 0.24, y: bCenter.y + bSize * 0.18))
    ctx.addPath(check)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(size * 0.02)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
    
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
