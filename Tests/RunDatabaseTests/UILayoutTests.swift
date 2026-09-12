import AppKit

/// 离屏布局回归：AppKit 在 CLI 进程里也能完成 Auto Layout 与文本排版，
/// 这里把最容易「换个状态就跑偏」的三块界面各摆一遍并断言关键 frame。
/// 新增断言时优先复用同一实例做状态切换 —— 新建视图往往是对的，复用后才会漂。
struct UILayoutTests {
    func runAll() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try testMenuBarCardKeepsTitleBlockCenteredAcrossSnapshots()
        try testMenuBarCardCollapsesEmptyLyricRow()
        try testLyricsViewStylesAndCentersActiveLine()
        try testTrackListCellStylesPlayingRow()
    }

    // MARK: - 菜单栏卡片

    private func testMenuBarCardKeepsTitleBlockCenteredAcrossSnapshots() throws {
        let card = MenuBarNowPlayingCardView()
        let window = host(card, size: NSSize(width: 320, height: 200))
        let withArtist = snapshot(title: "九万字", artist: "黄诗扶", lyric: "编曲 : 李大白")
        let noArtist = snapshot(title: "江湖之间", artist: nil, lyric: "陈亦洺/王韩伊淋")
        let steps: [(String, NowPlayingSnapshot?)] = [
            ("with", withArtist), ("without", noArtist), ("with-again", withArtist),
            ("nil", nil), ("without-after-nil", noArtist), ("with-after-nil", withArtist)
        ]

        for (step, current) in steps {
            card.apply(current)
            fit(window)
            let art = try firstImageView(in: card)
            let title = try textField(in: card, matching: current?.title ?? "未在播放")
            guard let block = title.superview else {
                throw TestFailure.message("[\(step)] title label should sit inside the text stack")
            }
            let artFrame = card.convert(art.bounds, from: art)
            let blockFrame = card.convert(block.bounds, from: block)
            try assertTrue(
                abs(blockFrame.midY - artFrame.midY) <= 1,
                "[\(step)] title block midY \(blockFrame.midY) should match artwork midY \(artFrame.midY)"
            )
            try assertTrue(
                blockFrame.minY >= artFrame.minY - 0.5 && blockFrame.maxY <= artFrame.maxY + 0.5,
                "[\(step)] title block \(blockFrame) should stay within the artwork span \(artFrame)"
            )
            try assertTrue(
                abs(blockFrame.minX - (artFrame.maxX + 10)) <= 0.5,
                "[\(step)] title block should start 10pt after the artwork"
            )
        }
    }

    private func testMenuBarCardCollapsesEmptyLyricRow() throws {
        let card = MenuBarNowPlayingCardView()
        let window = host(card, size: NSSize(width: 320, height: 200))

        card.apply(snapshot(title: "歌名", artist: "歌手", lyric: "一句歌词"))
        let withLyric = fit(window).height
        card.apply(snapshot(title: "歌名", artist: "歌手", lyric: nil))
        let withoutLyric = fit(window).height

        try assertEqual(withLyric.rounded(), 172, "card with lyric row")
        try assertTrue(withLyric - withoutLyric >= 15, "empty lyric row should collapse, got \(withLyric) vs \(withoutLyric)")
    }

    // MARK: - 歌词区

    private func testLyricsViewStylesAndCentersActiveLine() throws {
        let lyrics = LyricsView(frame: .zero)
        let window = host(lyrics, size: NSSize(width: 480, height: 320))
        window.contentView?.layoutSubtreeIfNeeded()

        let lines = (0..<30).map { LrcLine(time: Double($0) * 2, text: "第 \($0) 行歌词") }
        lyrics.render(lines)
        lyrics.update(for: 30.5, forceScroll: true)
        guard let textView = lyrics.documentView as? NSTextView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            throw TestFailure.message("lyrics view should host an NSTextView")
        }
        textView.layoutSubtreeIfNeeded()
        layoutManager.ensureLayout(for: container)

        let profile = LyricsDisplayProfile.standard
        let text = storage.string as NSString
        let active = text.range(of: "第 15 行歌词")
        let neighbor = text.range(of: "第 14 行歌词")
        let far = text.range(of: "第 0 行歌词")
        try assertTrue(active.location != NSNotFound, "active line should be in the text")

        let activeFont = try font(in: storage, at: active.location)
        try assertEqual(activeFont.pointSize, profile.activeFontSize, "active line size")
        // 中文字符经字体替换后 textStorage 里存的是 PingFang，不能比字体名，看粗体特征。
        try assertTrue(activeFont.fontDescriptor.symbolicTraits.contains(.bold), "active line should be bold, got \(activeFont.fontName)")
        let neighborFont = try font(in: storage, at: neighbor.location)
        try assertEqual(neighborFont.pointSize, profile.baseFontSize - 0.75, "neighbor line size")
        try assertTrue(!neighborFont.fontDescriptor.symbolicTraits.contains(.bold), "neighbor line should not be bold")
        try assertEqual(try font(in: storage, at: far.location).pointSize, profile.baseFontSize - 2, "far line size floors at base - 2")

        let glyphs = layoutManager.glyphRange(forCharacterRange: active, actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        lineRect.origin.x += textView.textContainerOrigin.x
        lineRect.origin.y += textView.textContainerOrigin.y
        let visible = lyrics.contentView.bounds
        try assertTrue(
            abs(lineRect.midY - visible.midY) <= 2,
            "active line midY \(lineRect.midY) should sit at the viewport center \(visible.midY)"
        )
    }

    // MARK: - 曲目列表

    private func testTrackListCellStylesPlayingRow() throws {
        let dataSource = TrackListDataSource()
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Track"))
        column.width = 300
        tableView.addTableColumn(column)
        dataSource.configure(tableView: tableView)

        let playingURL = URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/歌手 - 正在播放.mp3")
        dataSource.tracks = [
            MusicTrack(
                audioURL: URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/普通.mp3"),
                lyricURL: URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/普通.lrc"),
                title: "普通",
                artist: "某人",
                album: "专辑"
            ),
            MusicTrack(audioURL: playingURL),
            MusicTrack(audioURL: URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/无歌词.mp3"), title: "无歌词")
        ]
        dataSource.playingTrackURL = playingURL
        tableView.reloadData()

        let rowHeight = dataSource.tableView(tableView, heightOfRow: 1)
        let playing = try cell(dataSource, tableView, column, row: 1, height: rowHeight)
        try assertEqual(playing.title.stringValue, "正在播放", "无 ID3 时按文件名「歌手 - 歌名」拆分")
        try assertEqual(playing.subtitle.stringValue, "歌手 · 无歌词")
        try assertTrue(abs(weight(of: playing.title.font) - NSFont.Weight.semibold.rawValue) < 0.01, "playing title should be semibold, got \(weight(of: playing.title.font))")

        let normal = try cell(dataSource, tableView, column, row: 0, height: rowHeight)
        try assertEqual(normal.title.stringValue, "普通")
        try assertEqual(normal.subtitle.stringValue, "某人 · 专辑")
        try assertTrue(abs(weight(of: normal.title.font) - NSFont.Weight.regular.rawValue) < 0.01, "normal title should be regular, got \(weight(of: normal.title.font))")

        let noLyric = try cell(dataSource, tableView, column, row: 2, height: rowHeight)
        try assertEqual(noLyric.subtitle.stringValue, "无歌词")

        // 双行排版：标题距顶 7pt、左 10pt，副标题紧贴标题下 1pt。
        // 约束作用在 alignment rect 上，label 的 frame 比它每边多 2pt 内边距，要换算后再比。
        let titleFrame = playing.title.alignmentRect(forFrame: playing.title.frame)
        let subtitleFrame = playing.subtitle.alignmentRect(forFrame: playing.subtitle.frame)
        try assertEqual((rowHeight - titleFrame.maxY).rounded(), 7, "title top inset")
        try assertEqual(titleFrame.minX.rounded(), 10, "title leading inset")
        try assertTrue(abs(titleFrame.minY - 1 - subtitleFrame.maxY) <= 0.5, "subtitle should hug the title")
        try assertTrue(subtitleFrame.minY >= 0, "subtitle should stay inside the row")
    }

    // MARK: - helpers

    private func snapshot(title: String, artist: String?, lyric: String?) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            artwork: nil,
            lyricLine: lyric,
            currentTime: 8,
            duration: 214,
            isPlaying: true,
            mode: .sequential,
            volume: 1
        )
    }

    /// 把视图钉满一个离屏窗口；卡片这类自撑高的视图之后用 fit() 收缩窗口到 fittingSize。
    private func host(_ view: NSView, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = root
        view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        return window
    }

    @discardableResult
    private func fit(_ window: NSWindow) -> NSSize {
        guard let root = window.contentView else {
            return .zero
        }
        let size = root.fittingSize
        if window.frame.size != size {
            window.setContentSize(size)
        }
        root.layoutSubtreeIfNeeded()
        return size
    }

    private func cell(
        _ dataSource: TrackListDataSource,
        _ tableView: NSTableView,
        _ column: NSTableColumn,
        row: Int,
        height: CGFloat
    ) throws -> (title: NSTextField, subtitle: NSTextField) {
        guard let view = dataSource.tableView(tableView, viewFor: column, row: row) else {
            throw TestFailure.message("row \(row) should produce a cell view")
        }
        view.frame = NSRect(x: 0, y: 0, width: column.width, height: height)
        view.layoutSubtreeIfNeeded()
        let labels = textFields(in: view)
        guard labels.count == 2 else {
            throw TestFailure.message("row \(row) cell should have title + subtitle, found \(labels.count) labels")
        }
        return (labels[0], labels[1])
    }

    /// 系统字体描述符里的数值字重（regular 0、medium 0.23、semibold 0.3、bold 0.4）。
    private func weight(of font: NSFont?) -> CGFloat {
        let traits = font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return CGFloat((traits?[.weight] as? NSNumber)?.doubleValue ?? 0)
    }

    private func font(in storage: NSTextStorage, at location: Int) throws -> NSFont {
        guard let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont else {
            throw TestFailure.message("no font attribute at \(location)")
        }
        return font
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField {
            found.append(field)
        }
        for subview in view.subviews {
            found.append(contentsOf: textFields(in: subview))
        }
        return found
    }

    private func textField(in view: NSView, matching text: String) throws -> NSTextField {
        guard let field = textFields(in: view).first(where: { $0.stringValue == text }) else {
            throw TestFailure.message("no label showing \"\(text)\"")
        }
        return field
    }

    private func firstImageView(in view: NSView) throws -> NSImageView {
        func search(_ view: NSView) -> NSImageView? {
            if let image = view as? NSImageView {
                return image
            }
            for subview in view.subviews {
                if let hit = search(subview) {
                    return hit
                }
            }
            return nil
        }
        guard let image = search(view) else {
            throw TestFailure.message("no NSImageView found")
        }
        return image
    }
}
