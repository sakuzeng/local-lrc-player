import AppKit

final class LyricCandidateDialog: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case header(LyricProvider)
        case candidate(ScoredLyricCandidate)
    }

    private let service: LyricSearchService
    private let track: MusicTrack
    private let rows: [Row]
    private let replaceExisting: Bool
    private let completion: (Result<URL, Error>) -> Void

    private let tableView = NSTableView()
    private let previewTextView = NSTextView()
    private let saveButton = NSButton(title: "保存所选歌词", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "选择一个候选结果以预览歌词")

    private var selectedLyric: String?
    private var selectedCandidateRow: Int?

    init(
        service: LyricSearchService,
        track: MusicTrack,
        sections: [LyricCandidateSection],
        replaceExisting: Bool = false,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.service = service
        self.track = track
        self.rows = Self.makeRows(from: sections)
        self.replaceExisting = replaceExisting
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "选择歌词：\(track.displayName)"
        window.minSize = NSSize(width: 760, height: 460)
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showModal() {
        guard let window else {
            return
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeRows(from sections: [LyricCandidateSection]) -> [Row] {
        var rows: [Row] = []
        for section in sections {
            rows.append(.header(section.provider))
            rows.append(contentsOf: section.candidates.map { .candidate($0) })
        }
        return rows
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        setupTable()
        setupPreview()

        saveButton.target = self
        saveButton.action = #selector(saveSelectedLyric)
        saveButton.isEnabled = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let tableScrollView = NSScrollView()
        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.borderType = .lineBorder

        let previewScrollView = NSScrollView()
        previewScrollView.documentView = previewTextView
        previewScrollView.hasVerticalScroller = true
        previewScrollView.borderType = .lineBorder

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(tableScrollView)
        splitView.addArrangedSubview(previewScrollView)
        tableScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        tableScrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let buttons = NSStackView(views: [statusLabel, saveButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let root = NSStackView(views: [splitView, buttons])
        root.orientation = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            splitView.widthAnchor.constraint(equalTo: root.widthAnchor),
            splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])

        tableView.reloadData()
        if let firstCandidateRow = rows.firstIndex(where: { if case .candidate = $0 { return true }; return false }) {
            tableView.selectRowIndexes(IndexSet(integer: firstCandidateRow), byExtendingSelection: false)
            loadPreview(for: firstCandidateRow)
        }
    }

    private func setupTable() {
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "候选结果"
        titleColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(titleColumn)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 52
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
    }

    private func setupPreview() {
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        previewTextView.textContainerInset = NSSize(width: 14, height: 14)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard rows.indices.contains(row) else {
            return false
        }
        if case .header = rows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else {
            return 52
        }
        if case .header = rows[row] {
            return 30
        }
        return 52
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else {
            return false
        }
        if case .header = rows[row] {
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else {
            return nil
        }

        switch rows[row] {
        case .header(let provider):
            let identifier = NSUserInterfaceItemIdentifier("SectionHeaderCell")
            let textField: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                textField = reused
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = identifier
                textField.font = .systemFont(ofSize: 12, weight: .semibold)
                textField.textColor = .secondaryLabelColor
            }
            textField.stringValue = provider.displayName
            return textField

        case .candidate(let candidate):
            let identifier = NSUserInterfaceItemIdentifier("CandidateCell")
            let textField: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                textField = reused
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = identifier
                textField.maximumNumberOfLines = 2
                textField.lineBreakMode = .byTruncatingTail
                textField.font = .systemFont(ofSize: 13)
            }

            textField.stringValue = "\(candidate.displayTitle)\n\(candidate.detail)"
            return textField
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .candidate = rows[row] else {
            return
        }
        loadPreview(for: row)
    }

    private func loadPreview(for row: Int) {
        guard rows.indices.contains(row), case .candidate(let candidate) = rows[row] else {
            return
        }

        selectedCandidateRow = row
        selectedLyric = nil
        saveButton.isEnabled = false
        previewTextView.string = "正在加载歌词预览..."
        statusLabel.stringValue = "正在预览：\(candidate.candidate.provider.displayName) · \(candidate.displayTitle)"

        service.formattedLyric(for: candidate.candidate) { [weak self] result in
            guard let self, self.selectedCandidateRow == row else {
                return
            }

            switch result {
            case .failure(let error):
                self.previewTextView.string = "预览失败：\(error.localizedDescription)"
                self.statusLabel.stringValue = "预览失败"
            case .success(let lyric):
                self.selectedLyric = lyric
                self.previewTextView.string = lyric
                self.saveButton.isEnabled = true
                self.statusLabel.stringValue = "预览已加载：\(candidate.candidate.provider.displayName) · \(candidate.displayTitle)"
            }
        }
    }

    @objc private func saveSelectedLyric() {
        guard let selectedLyric else {
            return
        }

        do {
            let url = try service.saveFormattedLyric(selectedLyric, for: track, replaceExisting: replaceExisting)
            completion(.success(url))
            closeModal()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func cancel() {
        completion(.failure(LyricCandidateDialogError.cancelled))
        closeModal()
    }

    private func closeModal() {
        if let window {
            window.close()
        }
    }
}

enum LyricCandidateDialogError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        "已取消"
    }
}
