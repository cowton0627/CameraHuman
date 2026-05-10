#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputPath = "/Users/chunlicheng/Desktop/CameraHuman/CameraHuman/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let canvas: Int = 1024
let s = CGFloat(canvas)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create context\n", stderr)
    exit(1)
}

// 背景：暮色漸層（top warm → bottom deep purple）
let bgColors: CFArray = [
    CGColor(red: 1.00, green: 0.55, blue: 0.34, alpha: 1.0),
    CGColor(red: 0.96, green: 0.30, blue: 0.42, alpha: 1.0),
    CGColor(red: 0.32, green: 0.10, blue: 0.42, alpha: 1.0),
    CGColor(red: 0.10, green: 0.06, blue: 0.22, alpha: 1.0)
] as CFArray
let bgLocations: [CGFloat] = [0.0, 0.45, 0.82, 1.0]
guard let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) else { exit(1) }
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// 白色 sun / lens disc，略偏下，模擬日落
let center = CGPoint(x: s / 2, y: s * 0.46)
let radius = s * 0.255

// 外圍柔光
let glowColors: CFArray = [
    CGColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 0.55),
    CGColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 0.0)
] as CFArray
guard let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) else { exit(1) }
ctx.drawRadialGradient(
    glowGradient,
    startCenter: center,
    startRadius: radius * 0.95,
    endCenter: center,
    endRadius: radius * 1.95,
    options: []
)

// 主圓盤
ctx.setFillColor(CGColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 1.0))
ctx.fillEllipse(in: CGRect(
    x: center.x - radius,
    y: center.y - radius,
    width: radius * 2,
    height: radius * 2
))

// 圓盤內漸層（強調光感）
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: center.x - radius,
    y: center.y - radius,
    width: radius * 2,
    height: radius * 2
))
ctx.clip()
let discColors: CFArray = [
    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
    CGColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 0.30)
] as CFArray
guard let discGradient = CGGradient(colorsSpace: colorSpace, colors: discColors, locations: [0, 1]) else { exit(1) }
ctx.drawLinearGradient(
    discGradient,
    start: CGPoint(x: center.x, y: center.y + radius),
    end: CGPoint(x: center.x, y: center.y - radius),
    options: []
)
ctx.restoreGState()

// 地平線
let horizonY = center.y - radius * 0.10
let horizonInset = s * 0.08
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.85))
ctx.setLineWidth(s * 0.0125)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: horizonInset, y: horizonY))
ctx.addLine(to: CGPoint(x: s - horizonInset, y: horizonY))
ctx.strokePath()

// 第二條較細的副地平線（增加層次）
let horizonY2 = horizonY - s * 0.022
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.30))
ctx.setLineWidth(s * 0.005)
ctx.move(to: CGPoint(x: horizonInset * 1.6, y: horizonY2))
ctx.addLine(to: CGPoint(x: s - horizonInset * 1.6, y: horizonY2))
ctx.strokePath()

// 輸出 PNG
guard let image = ctx.makeImage() else {
    fputs("Failed to render image\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: outputPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Failed to open destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Failed to finalize PNG\n", stderr)
    exit(1)
}
print("Saved icon to \(outputPath)")
