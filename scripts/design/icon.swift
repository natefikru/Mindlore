import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Mindlore's icon: an ember disc on dark paper, and on it seven nodes joined by fine lines that read
// as a lowercase "m" and as a waveform. Voice becoming a graph. Usage: swift icon.swift <outdir>
let size = 1024
let out = CommandLine.arguments[1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

func draw(_ variant: Variant, to name: String) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let centre = CGPoint(x: 512, y: 512)

    // Background. Tinted icons are greyscale on black; the system supplies the tint.
    switch variant {
    case .light:
        let paper = CGGradient(colorsSpace: space, colors: [color(0xFFF3E6), color(0xFAE3CF)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
    case .dark:
        ctx.setFillColor(color(0x141210)); ctx.fill(full)
    case .tinted:
        ctx.setFillColor(color(0x000000)); ctx.fill(full)
    }

    // The ember disc, lit from the upper left, with a soft glow around it on the dark variants.
    let radius: CGFloat = 360
    if variant != .light {
        let glowColours = variant == .dark ? [color(0xFF8A55, 0.35), color(0xFF8A55, 0)] : [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)]
        let glow = CGGradient(colorsSpace: space, colors: glowColours as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: centre, startRadius: radius * 0.9, endCenter: centre, endRadius: radius * 1.4, options: [])
    }
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    let discColours = variant == .tinted ? [color(0xE6E6E6), color(0x8C8C8C)] : [color(0xFF9A5E), color(0xE0602B)]
    let disc = CGGradient(colorsSpace: space, colors: discColours as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(disc, startCenter: CGPoint(x: 400, y: 660), startRadius: 0, endCenter: centre, endRadius: radius * 1.15, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Seven nodes: up, over two humps, and down. The middle valley is what makes it an "m".
    let nodes: [(CGFloat, CGFloat, CGFloat)] = [
        (292, 392, 30), (292, 590, 24), (402, 664, 34), (512, 548, 26), (622, 664, 34), (732, 590, 24), (732, 392, 30)
    ]
    let mark = variant == .tinted ? color(0x000000) : color(0xFFF6EC)
    ctx.setStrokeColor(mark)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: nodes[0].0, y: nodes[0].1))
    for node in nodes.dropFirst() { ctx.addLine(to: CGPoint(x: node.0, y: node.1)) }
    ctx.strokePath()
    // Two fainter cross links, so it reads as a graph and not only as a letter.
    ctx.setStrokeColor(mark.copy(alpha: 0.45)!)
    ctx.setLineWidth(8)
    for (a, b) in [(1, 3), (3, 5)] {
        ctx.move(to: CGPoint(x: nodes[a].0, y: nodes[a].1))
        ctx.addLine(to: CGPoint(x: nodes[b].0, y: nodes[b].1))
    }
    ctx.strokePath()
    ctx.setFillColor(mark)
    for node in nodes {
        ctx.fillEllipse(in: CGRect(x: node.0 - node.2, y: node.1 - node.2, width: node.2 * 2, height: node.2 * 2))
    }

    let url = URL(fileURLWithPath: out).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

draw(.light, to: "AppIcon.png")
draw(.dark, to: "AppIcon-dark.png")
draw(.tinted, to: "AppIcon-tinted.png")
