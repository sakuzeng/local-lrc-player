import AppKit

final class TrackListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var tracks: [MusicTrack] = [] {
        didSet {
            tableView?.reloadData()
        }
    }

    var playingTrackURL: URL? {
        didSet {
            refreshRowAppearance()
        }
    }

    private(set) var selectedTrackURL: URL?

    var onDoubleClick: ((Int) -> Void)?
    var onSelectionChanged: ((Int?) -> Void)?

    private weak var tableView: NSTableView?

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

    func selectRow(_ row: Int, scrollToVisible: Bool = true) {
        guard tracks.indices.contains(row), let tableView else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        selectedTrackURL = tracks[row].audioURL
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tracks.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("TrackCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.isBordered = false
            textField.drawsBackground = false
            textField.backgroundColor = .clear
            textField.refusesFirstResponder = true
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        guard let textField = cell.textField else {
            return cell
        }

        let track = tracks[row]
        let isPlaying = isPlayingTrack(track)
        let isSelected = tableView.selectedRow == row
        textField.stringValue = displayText(for: track)
        applyTextStyle(to: textField, track: track, isPlaying: isPlaying, isSelected: isSelected)
        return cell
    }

    private func applyTextStyle(
        to textField: NSTextField,
        track: MusicTrack,
        isPlaying: Bool,
        isSelected: Bool
    ) {
        if isPlaying {
            textField.font = .boldSystemFont(ofSize: 14)
            textField.textColor = .controlAccentColor
            return
        }
        if isSelected {
            textField.font = .systemFont(ofSize: 14, weight: .medium)
            textField.textColor = .labelColor
            return
        }
        textField.font = .systemFont(ofSize: 14)
        textField.textColor = track.lyricURL == nil ? .secondaryLabelColor : .labelColor
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("TrackRow")
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? TrackRowView
            ?? TrackRowView()
        rowView.identifier = identifier
        rowView.isPlayingRow = tracks.indices.contains(row) && isPlayingTrack(tracks[row])
        return rowView
    }

    private func isPlayingTrack(_ track: MusicTrack) -> Bool {
        guard let playingTrackURL else {
            return false
        }
        return Self.matchesTrackURL(track.audioURL, playingTrackURL)
    }

    private func displayText(for track: MusicTrack) -> String {
        if track.lyricURL == nil {
            return "\(track.displayName)  ·  无歌词"
        }
        return track.displayName
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
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
        onDoubleClick?(row)
    }
}

/// 列表行样式（自定义，不用系统蓝色选中块）：
/// - 仅选中：浅灰底
/// - 正在播放：主题色浅底 + 加粗主题色文字
/// - 选中且正在播放：更深主题色浅底 + 左侧竖条
private final class TrackRowView: NSTableRowView {
    var isPlayingRow = false {
        didSet {
            needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isPlayingRow && isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            dirtyRect.fill()
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
            return
        }
        if isPlayingRow {
            NSColor.controlAccentColor.withAlphaComponent(0.11).setFill()
            dirtyRect.fill()
            return
        }
        if isSelected {
            NSColor.secondaryLabelColor.withAlphaComponent(0.16).setFill()
            dirtyRect.fill()
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
