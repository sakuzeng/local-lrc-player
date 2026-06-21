import AppKit

final class TrackListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var tracks: [MusicTrack] = [] {
        didSet {
            tableView?.reloadData()
        }
    }

    var playingTrackURL: URL? {
        didSet {
            tableView?.reloadData()
        }
    }

    var onDoubleClick: ((Int) -> Void)?
    var onSelectionChanged: (() -> Void)?

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
    }

    func indexOfPlayingTrack() -> Int? {
        guard let playingTrackURL else {
            return nil
        }
        return tracks.firstIndex { Self.matchesTrackURL($0.audioURL, playingTrackURL) }
    }

    func selectRow(_ row: Int, scrollToVisible: Bool = true) {
        guard tracks.indices.contains(row), let tableView else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if scrollToVisible {
            scrollRowToVisible(row)
        }
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        tracks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tracks.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("TrackCell")
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = reused
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingMiddle
        }

        let track = tracks[row]
        let isPlaying = isPlayingTrack(track)
        textField.stringValue = displayText(for: track)
        textField.font = isPlaying
            ? .boldSystemFont(ofSize: 14)
            : .systemFont(ofSize: 14)
        if isPlaying {
            textField.textColor = .controlAccentColor
        } else {
            textField.textColor = track.lyricURL == nil ? .secondaryLabelColor : .labelColor
        }
        return textField
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("TrackRow")
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? PlayingTrackRowView
            ?? PlayingTrackRowView()
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
        onSelectionChanged?()
    }

    @objc private func trackDoubleClicked() {
        guard let row = tableView?.clickedRow, tracks.indices.contains(row) else {
            return
        }
        onDoubleClick?(row)
    }
}

private final class PlayingTrackRowView: NSTableRowView {
    var isPlayingRow = false {
        didSet {
            needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isPlayingRow {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            dirtyRect.fill()
            return
        }
        super.drawBackground(in: dirtyRect)
    }
}
