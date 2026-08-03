import AppKit

final class TrackListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var tracks: [MusicTrack] = [] {
        didSet {
            hoveredRow = nil
            tableView?.reloadData()
        }
    }

    var playingTrackURL: URL? {
        didSet {
            refreshRowAppearance()
        }
    }

    private(set) var selectedTrackURL: URL?
    /// 用户主动点选的行；程序同步播放行时不设置，用于空格/菜单栏区分「暂停当前」与「切到选中曲」。
    private(set) var userSelectedTrackIndex: Int?

    var onDoubleClick: ((Int) -> Void)?
    var onSelectionChanged: ((Int?) -> Void)?

    private weak var tableView: NSTableView?
    private var suppressSelectionCallback = false
    private var hoveredRow: Int?
    private var boundsObserver: NSObjectProtocol?

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    static func matchesTrackURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    func configure(tableView: NSTableView) {
        self.tableView = tableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(trackDoubleClicked)
        tableView.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            tableView.style = .plain
            tableView.selectionHighlightStyle = .none
            tableView.rowSizeStyle = .custom
        }

        if let trackTable = tableView as? TrackTableView {
            trackTable.hoverCoordinator = self
        }
        tableView.window?.acceptsMouseMovedEvents = true

        if let clipView = tableView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.syncHoverWithMouseLocation()
            }
        }
    }

    func updateHover(atScreenPoint screenPoint: NSPoint) {
        guard let tableView else {
            return
        }
        let localPoint = tableView.convert(screenPoint, from: nil)
        applyHover(at: localPoint)
    }

    func clearHover() {
        setHoveredRow(nil)
    }

    private func syncHoverWithMouseLocation() {
        guard let tableView, let window = tableView.window else {
            return
        }
        let localPoint = tableView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        applyHover(at: localPoint)
    }

    private func applyHover(at point: NSPoint) {
        guard let tableView else {
            return
        }

        guard NSPointInRect(point, tableView.bounds) else {
            setHoveredRow(nil)
            return
        }

        let row = tableView.row(at: point)
        guard row >= 0 else {
            setHoveredRow(nil)
            return
        }

        let rowRect = tableView.rect(ofRow: row)
        guard NSPointInRect(point, rowRect) else {
            setHoveredRow(nil)
            return
        }

        setHoveredRow(row)
    }

    private func setHoveredRow(_ row: Int?) {
        guard row != hoveredRow else {
            return
        }
        hoveredRow = row
        syncVisibleRowHoverStates()
    }

    private func syncVisibleRowHoverStates() {
        guard let tableView else {
            return
        }
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let trackRowView = rowView as? TrackRowView else {
                return
            }
            trackRowView.isHovered = hoveredRow == row
        }
    }

    func indexOfPlayingTrack() -> Int? {
        guard let playingTrackURL else {
            return nil
        }
        return tracks.firstIndex { Self.matchesTrackURL($0.audioURL, playingTrackURL) }
    }

    func indexOfSelectedTrack() -> Int? {
        if let row = selectedTrackIndex() {
            return row
        }
        guard let selectedTrackURL else {
            return nil
        }
        return tracks.firstIndex { Self.matchesTrackURL($0.audioURL, selectedTrackURL) }
    }

    func selectRow(_ row: Int, scrollToVisible: Bool = true, isUserInitiated: Bool = false) {
        guard tracks.indices.contains(row), let tableView else {
            return
        }
        suppressSelectionCallback = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressSelectionCallback = false
        selectedTrackURL = tracks[row].audioURL
        if isUserInitiated {
            userSelectedTrackIndex = row
        } else {
            userSelectedTrackIndex = nil
        }
        if scrollToVisible {
            scrollRowToVisible(row)
        }
        refreshRowAppearance()
    }

    func scrollToPlayingTrack() {
        guard let index = indexOfPlayingTrack() else {
            return
        }
        scrollRowToVisible(index)
    }

    func scrollRowToVisible(_ row: Int) {
        guard tracks.indices.contains(row), let tableView else {
            return
        }
        DispatchQueue.main.async {
            tableView.scrollRowToVisible(row)
        }
    }

    func selectedTrackIndex() -> Int? {
        guard let row = tableView?.selectedRow, tracks.indices.contains(row) else {
            return nil
        }
        return row
    }

    func refreshRowAppearance() {
        redrawVisibleRowViews()
        reloadVisibleCellText()
    }

    private func redrawVisibleRowViews() {
        guard let tableView else {
            return
        }
        tableView.enumerateAvailableRowViews { rowView, row in
            guard tracks.indices.contains(row), let trackRowView = rowView as? TrackRowView else {
                return
            }
            trackRowView.isPlayingRow = isPlayingTrack(tracks[row])
            trackRowView.needsDisplay = true
        }
    }

    private func reloadVisibleCellText() {
        guard let tableView else {
            return
        }
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else {
            return
        }
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: visibleRange.location ..< NSMaxRange(visibleRange)),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tracks.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        48
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tracks.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("TrackCell")
        let cell: TrackTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? TrackTableCellView {
            cell = reused
        } else {
            cell = TrackTableCellView()
            cell.identifier = identifier
        }

        let track = tracks[row]
        let isPlaying = isPlayingTrack(track)
        let isSelected = tableView.selectedRow == row
        cell.configure(
            track: track,
            isPlaying: isPlaying,
            isSelected: isSelected
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("TrackRow")
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? TrackRowView
            ?? TrackRowView()
        rowView.identifier = identifier
        rowView.isHovered = hoveredRow == row
        rowView.isPlayingRow = tracks.indices.contains(row) && isPlayingTrack(tracks[row])
        return rowView
    }

    private func isPlayingTrack(_ track: MusicTrack) -> Bool {
        guard let playingTrackURL else {
            return false
        }
        return Self.matchesTrackURL(track.audioURL, playingTrackURL)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !suppressSelectionCallback {
            userSelectedTrackIndex = selectedTrackIndex()
        }
        if let row = selectedTrackIndex() {
            selectedTrackURL = tracks[row].audioURL
        }
        redrawVisibleRowViews()
        reloadVisibleCellText()
        onSelectionChanged?(selectedTrackIndex())
    }

    @objc private func trackDoubleClicked() {
        guard let row = tableView?.clickedRow, tracks.indices.contains(row) else {
            return
        }
        userSelectedTrackIndex = row
        onDoubleClick?(row)
    }
}

// MARK: - Cell

private final class TrackTableCellView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(track: MusicTrack, isPlaying: Bool, isSelected: Bool) {
        let parts = Self.displayParts(for: track)
        titleLabel.stringValue = parts.title
        subtitleLabel.stringValue = parts.subtitle
        applyTextStyle(isPlaying: isPlaying, isSelected: isSelected, hasLyric: track.lyricURL != nil)
    }

    private func setup() {
        for label in [titleLabel, subtitleLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.backgroundColor = .clear
            label.refusesFirstResponder = true
            label.lineBreakMode = .byTruncatingTail
        }

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])
    }

    private func applyTextStyle(isPlaying: Bool, isSelected: Bool, hasLyric: Bool) {
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)

        if isPlaying {
            titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            titleLabel.textColor = .controlAccentColor
            subtitleLabel.textColor = .secondaryLabelColor
            return
        }
        if isSelected {
            titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
            titleLabel.textColor = .labelColor
            subtitleLabel.textColor = .secondaryLabelColor
            return
        }
        titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        titleLabel.textColor = hasLyric ? .labelColor : .secondaryLabelColor
        subtitleLabel.textColor = .tertiaryLabelColor
    }

    private static func displayParts(for track: MusicTrack) -> (title: String, subtitle: String) {
        let filenameStem = track.audioURL.deletingPathExtension().lastPathComponent
        let id3Title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id3Artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id3Title, !id3Title.isEmpty,
           let id3Artist, !id3Artist.isEmpty,
           !id3Title.contains(" - ") {
            return (
                id3Title,
                subtitleText(artist: id3Artist, album: track.album, hasLyric: track.lyricURL != nil)
            )
        }

        for source in [id3Title, filenameStem] {
            guard let source, !source.isEmpty, let parsed = MusicTrack.parseArtistTitle(source) else {
                continue
            }
            return (
                parsed.title,
                subtitleText(artist: parsed.artist, album: track.album, hasLyric: track.lyricURL != nil)
            )
        }

        if let id3Title, !id3Title.isEmpty {
            return (
                id3Title,
                subtitleText(artist: id3Artist, album: track.album, hasLyric: track.lyricURL != nil)
            )
        }

        return (
            filenameStem,
            subtitleText(artist: nil, album: track.album, hasLyric: track.lyricURL != nil)
        )
    }

    private static func subtitleText(artist: String?, album: String?, hasLyric: Bool) -> String {
        var parts: [String] = []
        if let artist, !artist.isEmpty {
            parts.append(artist)
        }
        if let album, !album.isEmpty {
            parts.append(album)
        }

        var text = parts.joined(separator: " · ")
        if !hasLyric {
            if text.isEmpty {
                return "无歌词"
            }
            text += " · 无歌词"
        }
        return text
    }
}

// MARK: - Row

/// 列表行样式（自定义，不用系统蓝色选中块）：
/// - 仅选中：浅灰底
/// - 正在播放：主题色浅底
/// - 选中且正在播放：更深主题色浅底
/// - 悬停：在以上状态上略加深，或默认浅灰底
private final class TrackRowView: NSTableRowView {
    var isPlayingRow = false {
        didSet {
            needsDisplay = true
        }
    }

    var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let fillRect = bounds
        if isPlayingRow && isSelected {
            NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.26 : 0.22).setFill()
            fillRect.fill()
            return
        }
        if isPlayingRow {
            NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.15 : 0.11).setFill()
            fillRect.fill()
            return
        }
        if isSelected {
            NSColor.secondaryLabelColor.withAlphaComponent(isHovered ? 0.20 : 0.16).setFill()
            fillRect.fill()
            return
        }
        if isHovered {
            NSColor.secondaryLabelColor.withAlphaComponent(0.10).setFill()
            fillRect.fill()
            return
        }
        super.drawBackground(in: dirtyRect)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // 选中高亮已在 drawBackground 中自定义绘制
    }

    override var isSelected: Bool {
        didSet {
            needsDisplay = true
        }
    }
}

// MARK: - Table

final class TrackTableView: NSTableView {
    weak var hoverCoordinator: TrackListDataSource?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner as AnyObject === self {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .activeInActiveApp,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hoverCoordinator?.updateHover(atScreenPoint: event.locationInWindow)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverCoordinator?.clearHover()
        super.mouseExited(with: event)
    }
}
