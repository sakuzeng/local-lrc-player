import AppKit

/// 封面取色。氛围背景与里程碑弹窗共用，避免各抄一份调参不一致。
enum ArtworkColor {
    /// 1x1 下采样取平均色；平均色常发灰，拉一把饱和度、把亮度压进中间段再用。
    static func dominant(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: 1, height: 1,
                  bitsPerComponent: 8, bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else {
            return nil
        }

        let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation * 1.6, 0.3), 0.85),
            brightness: min(max(brightness, 0.45), 0.8),
            alpha: 1
        )
    }

    static func shiftedHue(_ color: NSColor, by delta: CGFloat) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return color
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shifted = (hue + delta).truncatingRemainder(dividingBy: 1)
        return NSColor(
            hue: shifted < 0 ? shifted + 1 : shifted,
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
    }

    /// 文字用色：在浅色弹窗上要够深才压得住，所以单独压一档亮度、提一档饱和。
    static func readable(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return color
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // 饱和度给个下限：封面偏灰偏暗时（大量中文专辑图如此），
        // 否则大字会褪成一团灰紫，看不出是从封面取的色。
        return NSColor(
            hue: hue,
            saturation: min(max(saturation * 1.15, 0.5), 0.95),
            brightness: min(brightness, 0.62),
            alpha: 1
        )
    }
}
