import AppKit

enum MenuBarStatusItemVisibility {
    static let autosaveName = "locallrcplayer-lyrics"

    static func clearPersistedVisibility() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            guard shouldClear(key: key, value: defaults.object(forKey: key)) else {
                continue
            }
            defaults.removeObject(forKey: key)
        }
    }

    static func install(_ item: NSStatusItem) {
        clearPersistedVisibility()
        item.isVisible = true
        item.autosaveName = autosaveName
        item.isVisible = true

        DispatchQueue.main.async {
            item.isVisible = true
            refreshButtonAppearance(item.button)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            item.isVisible = true
            refreshButtonAppearance(item.button)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            item.isVisible = true
            refreshButtonAppearance(item.button)
        }
    }

    private static func shouldClear(key: String, value: Any?) -> Bool {
        if key.hasPrefix("NSStatusItem Preferred Position") {
            return key.contains(autosaveName) || isDefaultItemName(key: key)
        }

        if key.hasPrefix("NSStatusItem VisibleCC ") {
            let itemName = String(key.dropFirst("NSStatusItem VisibleCC ".count))
            guard isFalse(value) else {
                return false
            }
            return itemName == autosaveName || isDefaultItemName(itemName: itemName)
        }

        if key.hasPrefix("NSStatusItem Visible ") {
            let itemName = String(key.dropFirst("NSStatusItem Visible ".count))
            guard isFalse(value) else {
                return false
            }
            return itemName == autosaveName || isDefaultItemName(itemName: itemName)
        }

        return false
    }

    private static func isDefaultItemName(key: String) -> Bool {
        guard let itemName = key.split(separator: " ").last else {
            return false
        }
        return isDefaultItemName(itemName: String(itemName))
    }

    private static func isDefaultItemName(itemName: String) -> Bool {
        guard itemName.hasPrefix("Item-") else {
            return false
        }
        return itemName.dropFirst("Item-".count).allSatisfy(\.isNumber)
    }

    private static func isFalse(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber:
            return !number.boolValue
        case let bool as Bool:
            return !bool
        default:
            return false
        }
    }

    private static func refreshButtonAppearance(_ button: NSStatusBarButton?) {
        guard let button else {
            return
        }
        button.needsDisplay = true
        button.window?.displayIfNeeded()
    }
}
