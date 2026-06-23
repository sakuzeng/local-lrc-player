import AppKit

extension NSToolbarItem.Identifier {
    static let playerChooseFolder = NSToolbarItem.Identifier("playerChooseFolder")
    static let playerRefresh = NSToolbarItem.Identifier("playerRefresh")
    static let playerSearch = NSToolbarItem.Identifier("playerSearch")
}

final class PlayerWindowToolbar: NSObject, NSToolbarDelegate {
    static let toolbarIdentifier = NSToolbar.Identifier("PlayerWindowToolbar")

    private weak var controller: PlayerWindowController?
    private let layout: PlayerWindowLayout
    private var refreshItem: NSToolbarItem?

    init(controller: PlayerWindowController, layout: PlayerWindowLayout) {
        self.controller = controller
        self.layout = layout
        super.init()
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    func updateEnabledState(hasLibrary: Bool) {
        refreshItem?.isEnabled = hasLibrary
        layout.searchField.isEnabled = hasLibrary
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .playerChooseFolder,
            .playerRefresh,
            .flexibleSpace,
            .playerSearch
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .playerChooseFolder:
            return makeActionItem(
                identifier: itemIdentifier,
                label: "选择文件夹",
                symbolName: "folder.badge.plus",
                action: #selector(PlayerWindowController.chooseFolderFromMenu)
            )
        case .playerRefresh:
            let item = makeActionItem(
                identifier: itemIdentifier,
                label: "刷新",
                symbolName: "arrow.clockwise",
                action: #selector(PlayerWindowController.refreshFolderFromMenu)
            )
            refreshItem = item
            return item
        case .playerSearch:
            return makeSearchItem(identifier: itemIdentifier)
        default:
            return nil
        }
    }

    private func makeActionItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = controller
        item.action = action
        return item
    }

    private func makeSearchItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = ""

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        layout.searchField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(layout.searchField)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 240),
            container.heightAnchor.constraint(equalToConstant: 28),
            layout.searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            layout.searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            layout.searchField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        item.view = container
        return item
    }
}
