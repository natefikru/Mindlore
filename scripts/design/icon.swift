import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Mindlore's icon: an ember disc on paper, and on it seven nodes joined by fine lines that read as
// a lowercase "m" and as a waveform. Voice becoming a graph.
//
// It ships as a layered Icon Composer document, `Mindlore/AppIcon.icon`: the paper is the
// document's own fill (a warm gradient, near black in dark mode), and the disc and the mark are two
// layers in their own glass groups, so iOS draws the specular edge, the clear and tinted looks, and
// the depth between them. This script draws those two layers; `icon.json` beside them says how they
// stack. Usage: swift scripts/design/icon.swift Mindlore/AppIcon.icon/Assets
let size = 1024
let out = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let centre = CGPoint(x: 512, y: 512)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func layer(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let url = URL(fileURLWithPath: out).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

// The ember disc, lit from the upper left. The glass adds the highlight and the edge.
layer("disc.png") { ctx in
    let radius: CGFloat = 360
    ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    let disc = CGGradient(colorsSpace: space, colors: [color(0xFF9A5E), color(0xE0602B)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(disc, startCenter: CGPoint(x: 400, y: 660), startRadius: 0, endCenter: centre, endRadius: radius * 1.15, options: [.drawsAfterEndLocation])
}

// Seven nodes: up, over two humps, and down. The middle valley is what makes it an "m". Two fainter
// cross links make it read as a graph and not only as a letter.
layer("mark.png") { ctx in
    let nodes: [(CGFloat, CGFloat, CGFloat)] = [
        (292, 392, 30), (292, 590, 24), (402, 664, 34), (512, 548, 26), (622, 664, 34), (732, 590, 24), (732, 392, 30)
    ]
    let mark = color(0xFFF6EC)
    ctx.setStrokeColor(mark)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: nodes[0].0, y: nodes[0].1))
    for node in nodes.dropFirst() { ctx.addLine(to: CGPoint(x: node.0, y: node.1)) }
    ctx.strokePath()
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
}
