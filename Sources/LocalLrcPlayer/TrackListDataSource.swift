import AppKit

final class TrackListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var tracks: [MusicTrack] = [] {
        didSet {
            tableView?.reloadData()
        }
    }

    var onDoubleClick: ((Int) -> Void)?

    private weak var tableView: NSTableView?

    func configure(tableView: NSTableView) {
        self.tableView = tableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(trackDoubleClicked)
    }

    func selectRow(_ row: Int) {
        guard tracks.indices.contains(row) else {
            return
        }
        tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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
            textField.font = .systemFont(ofSize: 14)
        }

        let track = tracks[row]
        textField.stringValue = track.lyricURL == nil ? "\(track.displayName)  ·  无歌词" : track.displayName
        textField.textColor = track.lyricURL == nil ? .secondaryLabelColor : .labelColor
        return textField
    }

    @objc private func trackDoubleClicked() {
        guard let row = tableView?.clickedRow, tracks.indices.contains(row) else {
            return
        }
        onDoubleClick?(row)
    }
}
