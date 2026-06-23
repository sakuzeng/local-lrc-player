import AppKit

enum AppMenuBuilder {
    static func installMainMenu(
        playerWindowController: PlayerWindowController,
        menuBarLyricsController: MenuBarLyricsController
    ) {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem(playerWindowController: playerWindowController))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(playbackMenuItem(playerWindowController: playerWindowController))
        mainMenu.addItem(viewMenuItem(menuBarLyricsController: menuBarLyricsController))
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = mainMenu.item(withTitle: "窗口")?.submenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Local LRC Player", action: #selector(AppDelegate.showAboutPanel), keyEquivalent: "")
        appMenu.item(at: 0)?.target = AppDelegate.shared
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(
            title: "设置…",
            action: #selector(AppDelegate.showSettings),
            keyEquivalent: ",",
            target: AppDelegate.shared
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Local LRC Player", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Local LRC Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = appMenu
        return item
    }

    private static func fileMenuItem(playerWindowController: PlayerWindowController) -> NSMenuItem {
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(menuItem(
            title: "选择文件夹…",
            action: #selector(PlayerWindowController.chooseFolderFromMenu),
            keyEquivalent: "o",
            target: playerWindowController
        ))
        fileMenu.addItem(menuItem(
            title: "刷新全部文件夹",
            action: #selector(PlayerWindowController.refreshFolderFromMenu),
            keyEquivalent: "r",
            target: playerWindowController
        ))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem(
            title: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w",
            target: nil
        ))

        let item = NSMenuItem()
        item.title = "文件"
        item.submenu = fileMenu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(menuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z", target: nil))
        editMenu.addItem(menuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z", target: nil))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x", target: nil))
        editMenu.addItem(menuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c", target: nil))
        editMenu.addItem(menuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v", target: nil))
        editMenu.addItem(menuItem(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{8}", target: nil))
        editMenu.addItem(menuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", target: nil))

        let item = NSMenuItem()
        item.title = "编辑"
        item.submenu = editMenu
        return item
    }

    private static func playbackMenuItem(playerWindowController: PlayerWindowController) -> NSMenuItem {
        let playbackMenu = NSMenu(title: "播放")
        playbackMenu.addItem(menuItem(
            title: "播放/暂停",
            action: #selector(PlayerWindowController.togglePlaybackFromMenu),
            keyEquivalent: " ",
            target: playerWindowController
        ))
        playbackMenu.addItem(menuItem(
            title: "上一首",
            action: #selector(PlayerWindowController.playPreviousFromMenu),
            keyEquivalent: "[",
            target: playerWindowController
        ))
        playbackMenu.addItem(menuItem(
            title: "下一首",
            action: #selector(PlayerWindowController.playNextFromMenu),
            keyEquivalent: "]",
            target: playerWindowController
        ))

        let item = NSMenuItem()
        item.title = "播放"
        item.submenu = playbackMenu
        return item
    }

    private static func viewMenuItem(menuBarLyricsController: MenuBarLyricsController) -> NSMenuItem {
        let viewMenu = NSMenu(title: "视图")
        viewMenu.delegate = menuBarLyricsController
        MenuBarLyricsSettingsMenu.appendSettings(to: viewMenu, controller: menuBarLyricsController, leadingSeparator: false)
        MenuBarLyricsSettingsMenu.refreshCheckmarks(
            in: viewMenu,
            settings: menuBarLyricsController.currentSettingsSnapshot()
        )

        let item = NSMenuItem()
        item.title = "视图"
        item.submenu = viewMenu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(menuItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
            target: nil
        ))
        windowMenu.addItem(menuItem(
            title: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "",
            target: nil
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem(
            title: "全部置于顶层",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "",
            target: nil
        ))

        let item = NSMenuItem()
        item.title = "窗口"
        item.submenu = windowMenu
        return item
    }

    private static func helpMenuItem() -> NSMenuItem {
        let helpMenu = NSMenu(title: "帮助")
        helpMenu.addItem(menuItem(
            title: "Local LRC Player 帮助",
            action: #selector(AppDelegate.showHelp),
            keyEquivalent: "?",
            target: AppDelegate.shared,
            modifierMask: [.command, .shift]
        ))

        let item = NSMenuItem()
        item.title = "帮助"
        item.submenu = helpMenu
        return item
    }

    private static func menuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String,
        target: AnyObject?,
        modifierMask: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifierMask
        }
        return item
    }
}
