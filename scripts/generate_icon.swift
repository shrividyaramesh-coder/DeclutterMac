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
    
    // Deep Space Obsidian Canvas with subtle vertical lighting
    let bgColors = [
        CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        
        // Radiant Cyan/Mint Ambient Core Glow
        let glowColors = [
            CGColor(red: 0.0, green: 0.75, blue: 0.95, alpha: 0.38),
            CGColor(red: 0.18, green: 0.85, blue: 0.55, alpha: 0.18),
            CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ] as CFArray
        if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0]) {
            ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: rect.midX, y: rect.midY + size * 0.05), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.62, options: [])
        }
        ctx.restoreGState()
    }
    
    // Apple Glass Bevel Rim
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.016)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.strokePath()
    ctx.restoreGState()
    
    // 2. Modern Mac Display Silhouette (iMac / Studio Display Aesthetic)
    let mWidth = size * 0.68
    let mHeight = size * 0.44
    let mX = (size - mWidth) / 2
    let mY = size * 0.36
    let mRadius = size * 0.035
    
    let monitorRect = CGRect(x: mX, y: mY, width: mWidth, height: mHeight)
    let monitorPath = CGPath(roundedRect: monitorRect, cornerWidth: mRadius, cornerHeight: mRadius, transform: nil)
    
    // Monitor Drop Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.035), blur: size * 0.07, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
    
    // Monitor Frame: Dark Titanium with subtle edge
    let frameColors = [
        CGColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1.0)
    ] as CFArray
    if let frameGrad = CGGradient(colorsSpace: colorSpace, colors: frameColors, locations: [0.0, 1.0]) {
        ctx.addPath(monitorPath)
        ctx.clip()
        ctx.drawLinearGradient(frameGrad, start: CGPoint(x: monitorRect.midX, y: monitorRect.maxY), end: CGPoint(x: monitorRect.midX, y: monitorRect.minY), options: [])
    }
    ctx.restoreGState()
    
    // Monitor Bevel Rim
    ctx.saveGState()
    ctx.addPath(monitorPath)
    ctx.setLineWidth(size * 0.01)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.strokePath()
    ctx.restoreGState()
    
    // Monitor Screen (Glass Display with vibrant desktop aura)
    let screenInset = size * 0.02
    let screenRect = CGRect(x: mX + screenInset, y: mY + screenInset, width: mWidth - screenInset * 2, height: mHeight - screenInset * 2)
    let screenRadius = size * 0.022
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    
    // Screen Desktop Wallpaper Gradient (Deep Azure to Emerald Clean)
    let screenColors = [
        CGColor(red: 0.04, green: 0.18, blue: 0.38, alpha: 1.0),
        CGColor(red: 0.02, green: 0.09, blue: 0.22, alpha: 1.0)
    ] as CFArray
    if let sGrad = CGGradient(colorsSpace: colorSpace, colors: screenColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(sGrad, start: CGPoint(x: screenRect.midX, y: screenRect.maxY), end: CGPoint(x: screenRect.midX, y: screenRect.minY), options: [])
    }
    
    // Dynamic Decluttering Sweep Beam across screen
    let beamPath = CGMutablePath()
    beamPath.move(to: CGPoint(x: screenRect.minX - size * 0.1, y: screenRect.minY))
    beamPath.addLine(to: CGPoint(x: screenRect.midX + size * 0.1, y: screenRect.maxY))
    beamPath.addLine(to: CGPoint(x: screenRect.midX + size * 0.2, y: screenRect.maxY))
    beamPath.addLine(to: CGPoint(x: screenRect.minX + size * 0.05, y: screenRect.minY))
    beamPath.closeSubpath()
    
    let beamColors = [
        CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.0),
        CGColor(red: 0.15, green: 0.95, blue: 0.7, alpha: 0.35),
        CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let beamGrad = CGGradient(colorsSpace: colorSpace, colors: beamColors, locations: [0.0, 0.5, 1.0]) {
        ctx.saveGState()
        ctx.addPath(beamPath)
        ctx.clip()
        ctx.drawLinearGradient(beamGrad, start: CGPoint(x: screenRect.minX, y: screenRect.minY), end: CGPoint(x: screenRect.maxX, y: screenRect.maxY), options: [])
        ctx.restoreGState()
    }
    
    // Three Perfectly Aligned, Decluttered Floating File Cards on Screen
    struct ScreenCard {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
        let color: CGColor
        let accent: CGColor
    }
    let cW = screenRect.width * 0.24
    let cH = screenRect.height * 0.56
    let startX = screenRect.midX - cW * 1.5 - size * 0.015
    let cardY = screenRect.midY - cH * 0.48
    
    let cards: [ScreenCard] = [
        ScreenCard(x: startX, y: cardY, w: cW, h: cH,
                   color: CGColor(red: 0.10, green: 0.45, blue: 0.92, alpha: 0.92),
                   accent: CGColor(red: 0.45, green: 0.80, blue: 1.0, alpha: 1.0)),
        ScreenCard(x: startX + cW + size * 0.018, y: cardY + size * 0.01, w: cW, h: cH,
                   color: CGColor(red: 0.12, green: 0.72, blue: 0.55, alpha: 0.92),
                   accent: CGColor(red: 0.60, green: 1.0, blue: 0.82, alpha: 1.0)),
        ScreenCard(x: startX + (cW + size * 0.018) * 2, y: cardY, w: cW, h: cH,
                   color: CGColor(red: 0.55, green: 0.28, blue: 0.90, alpha: 0.92),
                   accent: CGColor(red: 0.85, green: 0.65, blue: 1.0, alpha: 1.0))
    ]
    
    for c in cards {
        let cRect = CGRect(x: c.x, y: c.y, width: c.w, height: c.h)
        let cPath = CGPath(roundedRect: cRect, cornerWidth: size * 0.016, cornerHeight: size * 0.016, transform: nil)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.02, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
        ctx.addPath(cPath)
        ctx.setFillColor(c.color)
        ctx.fillPath()
        
        // Card header line
        ctx.setStrokeColor(c.accent)
        ctx.setLineWidth(size * 0.008)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cRect.minX + size * 0.012, y: cRect.maxY - size * 0.015))
        ctx.addLine(to: CGPoint(x: cRect.maxX - size * 0.012, y: cRect.maxY - size * 0.015))
        ctx.strokePath()
        
        // Card content lines
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        ctx.setLineWidth(size * 0.005)
        ctx.move(to: CGPoint(x: cRect.minX + size * 0.012, y: cRect.maxY - size * 0.03))
        ctx.addLine(to: CGPoint(x: cRect.maxX - size * 0.02, y: cRect.maxY - size * 0.03))
        ctx.move(to: CGPoint(x: cRect.minX + size * 0.012, y: cRect.maxY - size * 0.042))
        ctx.addLine(to: CGPoint(x: cRect.maxX - size * 0.028, y: cRect.maxY - size * 0.042))
        ctx.strokePath()
        ctx.restoreGState()
    }
    
    ctx.restoreGState() // Screen clip
    
    // 3. Apple Display Stand (Sleek Tapered Aluminum Stand)
    let standW = size * 0.18
    let standH = size * 0.16
    let standX = (size - standW) / 2
    let standY = mY - standH + size * 0.015
    
    let standPath = CGMutablePath()
    standPath.move(to: CGPoint(x: standX + size * 0.02, y: mY))
    standPath.addLine(to: CGPoint(x: standX + standW - size * 0.02, y: mY))
    standPath.addLine(to: CGPoint(x: standX + standW, y: standY + size * 0.02))
    standPath.addArc(tangent1End: CGPoint(x: standX + standW, y: standY), tangent2End: CGPoint(x: standX, y: standY), radius: size * 0.01)
    standPath.addLine(to: CGPoint(x: standX, y: standY))
    standPath.addArc(tangent1End: CGPoint(x: standX, y: standY + size * 0.02), tangent2End: CGPoint(x: standX + size * 0.02, y: mY), radius: size * 0.01)
    standPath.closeSubpath()
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.03, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    let standColors = [
        CGColor(red: 0.35, green: 0.38, blue: 0.48, alpha: 1.0),
        CGColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 1.0)
    ] as CFArray
    if let standGrad = CGGradient(colorsSpace: colorSpace, colors: standColors, locations: [0.0, 1.0]) {
        ctx.addPath(standPath)
        ctx.clip()
        ctx.drawLinearGradient(standGrad, start: CGPoint(x: size/2, y: mY), end: CGPoint(x: size/2, y: standY), options: [])
    }
    ctx.restoreGState()
    
    // Stand Base Plate
    let baseW = size * 0.30
    let baseH = size * 0.022
    let baseX = (size - baseW) / 2
    let baseY = standY - size * 0.005
    let baseRect = CGRect(x: baseX, y: baseY, width: baseW, height: baseH)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: size * 0.01, cornerHeight: size * 0.01, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.03, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(basePath)
    ctx.setFillColor(CGColor(red: 0.28, green: 0.32, blue: 0.42, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()
    
    // 4. Prominent Emerald Declutter Badge / Checkmark Seal
    let bSize = size * 0.26
    let bCenter = CGPoint(x: size * 0.74, y: size * 0.30)
    let bRect = CGRect(x: bCenter.x - bSize/2, y: bCenter.y - bSize/2, width: bSize, height: bSize)
    let bCircle = CGPath(ellipseIn: bRect, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.06, color: CGColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.75))
    
    let sealColors = [
        CGColor(red: 0.20, green: 0.95, blue: 0.65, alpha: 1.0),
        CGColor(red: 0.05, green: 0.65, blue: 0.42, alpha: 1.0)
    ] as CFArray
    if let sGrad = CGGradient(colorsSpace: colorSpace, colors: sealColors, locations: [0.0, 1.0]) {
        ctx.addPath(bCircle)
        ctx.clip()
        ctx.drawLinearGradient(sGrad, start: CGPoint(x: bCenter.x, y: bRect.maxY), end: CGPoint(x: bCenter.x, y: bRect.minY), options: [])
        
        // Specular Rim
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.65))
        ctx.setLineWidth(size * 0.012)
        ctx.addPath(bCircle)
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // Crisp White Checkmark in Badge
    ctx.saveGState()
    let check = CGMutablePath()
    check.move(to: CGPoint(x: bCenter.x - bSize * 0.24, y: bCenter.y))
    check.addLine(to: CGPoint(x: bCenter.x - bSize * 0.06, y: bCenter.y - bSize * 0.18))
    check.addLine(to: CGPoint(x: bCenter.x + bSize * 0.26, y: bCenter.y + bSize * 0.18))
    ctx.addPath(check)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(size * 0.024)
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

// Also save 1024x1024 master icon for web/app-icon.png
let masterImg = createIconImage(size: 1024)
savePNG(image: masterImg, at: URL(fileURLWithPath: "web/app-icon.png"), pixelSize: 1024)

print("Generated new Declutter Mac iconset and web/app-icon.png successfully!")
