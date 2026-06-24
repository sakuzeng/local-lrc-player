import Foundation

enum LibraryBookmarkStore {
    private static let defaultsPrefix = "librarySecurityBookmark."
    private static var activeURLs: [URL] = []

    static func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: defaultsKey(for: url))
        } catch {
            // 某些路径在用户未授权前无法创建 bookmark。
        }
    }

    @discardableResult
    static func activateAccess(for url: URL) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: url)) else {
            return false
        }

        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return false
        }

        if stale {
            saveBookmark(for: resolved)
        }

        guard resolved.startAccessingSecurityScopedResource() else {
            return false
        }

        activeURLs.append(resolved)
        return true
    }

    static func activateLibraries(_ libraries: [LibraryRecord]) {
        for library in libraries {
            _ = activateAccess(for: library.url)
        }
    }

    /// 用户已通过系统弹窗授权、但尚未保存 bookmark 时，在成功访问后补存。
    static func persistBookmarkIfNeeded(for url: URL) {
        guard UserDefaults.standard.data(forKey: defaultsKey(for: url)) == nil else {
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        saveBookmark(for: url)
    }

    static func stopAll() {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }

    private static func defaultsKey(for url: URL) -> String {
        defaultsPrefix + url.standardizedFileURL.path
    }
}
