import AppKit

enum MenuBarLyricsStatusImage {
    static func make(
        text: String,
        width: CGFloat,
        showIcon: Bool,
        textOffsetX: CGFloat = 0
    ) -> NSImage {
        let thickness = max(NSStatusBar.system.thickness, 22)
        let size = NSSize(width: width, height: thickness)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let iconBlock: CGFloat = showIcon ? 16 : 0
        let textRect = NSRect(
            x: 6,
            y: 2,
            width: max(size.width - iconBlock - 10, 8),
            height: size.height - 4
        )

        let attributes = textAttributes()
        let displayText = text.isEmpty ? "Local LRC Player" : text
        let textSize = (displayText as NSString).size(withAttributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()

        let centeredY = textRect.minY + max((textRect.height - textSize.height) / 2, 0)
        let drawX: CGFloat
        if textOffsetX > 0 {
            drawX = textRect.minX - textOffsetX
        } else if textSize.width <= textRect.width {
            drawX = textRect.minX + (textRect.width - textSize.width) / 2
        } else {
            drawX = textRect.minX
        }
        (displayText as NSString).draw(
            at: NSPoint(x: drawX, y: centeredY),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()

        if showIcon {
            drawIcon(in: NSRect(
                x: size.width - iconBlock,
                y: (size.height - 12) / 2,
                width: 12,
                height: 12
            ))
        }

        return image
    }

    private static func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white
        ]
    }

    private static func drawIcon(in rect: NSRect) {
        let symbolNames = ["music.note", "music.note.list", "waveform"]
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        for name in symbolNames {
            guard let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else {
                continue
            }
            icon.isTemplate = true
            NSColor.white.set()
            icon.draw(in: rect)
            return
        }

        ("♪" as NSString).draw(in: rect, withAttributes: textAttributes())
    }

    static func preferredContentWidth(
        text: String,
        showIcon: Bool,
        maxWidth: CGFloat,
        useFullWidth: Bool
    ) -> CGFloat {
        let minimum = max(NSStatusItem.squareLength, 28)
        if useFullWidth {
            return max(maxWidth, minimum)
        }

        let displayText = text.isEmpty ? "Local LRC Player" : text
        let textSize = (displayText as NSString).size(withAttributes: textAttributes())
        let iconBlock: CGFloat = showIcon ? 16 : 0
        let padding: CGFloat = 16
        let contentWidth = textSize.width + iconBlock + padding
        return min(max(contentWidth, minimum), maxWidth)
    }
}
