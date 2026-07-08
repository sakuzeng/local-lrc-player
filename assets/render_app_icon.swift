// 一次性脚本:渲染 App 图标 1024px PNG(靛蓝渐变圆角方形 + 音符 + 歌词线)。
// 用法: swift assets/render_app_icon.swift assets/AppIcon-1024.png
// 之后由 assets/make_icns.sh 降采样并打包成 AppIcon.icns。
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

func tinted(_ image: NSImage, color: NSColor) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    copy.isTemplate = false
    return copy
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("无法创建位图") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 图标网格:1024 画布,内容区 824x824 圆角方形
let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: 186, yRadius: 186)

let topColor = NSColor(calibratedRed: 0.494, green: 0.404, blue: 0.941, alpha: 1)     // 紫
let bottomColor = NSColor(calibratedRed: 0.157, green: 0.153, blue: 0.478, alpha: 1)  // 深靛蓝
NSGradient(starting: topColor, ending: bottomColor)?.draw(in: squircle, angle: -70)

// 顶部柔光,避免纯平渐变发闷(全高渐变,防止出现接缝)
squircle.setClip()
let glow = NSGradient(starting: NSColor(white: 1, alpha: 0), ending: NSColor(white: 1, alpha: 0.18))
glow?.draw(in: iconRect, angle: 90)

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()

// 左侧:白色音符(SF Symbol);整组内容先测量总宽再水平居中,避免溢出圆角
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium)
guard let noteBase = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else { fatalError("取不到 music.note symbol") }
let note = tinted(noteBase, color: .white)
let noteHeight: CGFloat = 430
let noteWidth = note.size.width / note.size.height * noteHeight
let noteBarGap: CGFloat = 72
let bars: [(width: CGFloat, alpha: CGFloat)] = [(185, 0.5), (250, 1.0), (150, 0.5)]
let maxBarWidth = bars.map(\.width).max()!
let groupWidth = noteWidth + noteBarGap + maxBarWidth
let noteRect = NSRect(x: iconRect.midX - groupWidth / 2, y: 512 - noteHeight / 2,
                      width: noteWidth, height: noteHeight)
note.draw(in: noteRect, from: .zero, operation: .sourceOver, fraction: 1)

// 右侧:三条歌词线,中间为当前行(更亮更长)
let barHeight: CGFloat = 56
let barGap: CGFloat = 86
let barX = noteRect.maxX + noteBarGap
let totalHeight = barHeight * 3 + barGap * 2
var barY = 512 + totalHeight / 2 - barHeight
for bar in bars {
    let barRect = NSRect(x: barX, y: barY, width: bar.width, height: barHeight)
    NSColor(white: 1, alpha: bar.alpha).setFill()
    NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    barY -= barHeight + barGap
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 编码失败") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("written: \(outputPath)")
