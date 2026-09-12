import Foundation

/// 监听音乐文件夹的目录项变化（新增、删除、改名、原子替换），合并成一次回调。
/// 扫描只看顶层目录，所以每个库一个 DispatchSource 盯目录 vnode 就够。
/// 文件内容原地改写不会触发目录事件，但常见写法（临时文件 + rename）会。
final class LibraryFolderWatcher {
    /// 事件合并的静默窗口：批量拷贝会连发一串事件，等它停下来再同步；
    /// 也让正在拷贝中的文件有机会写完，免得先算出半个文件的哈希。
    var debounceInterval: TimeInterval = 2.0
    /// 主线程回调。
    var onChange: (() -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "local.lrc.player.folder-watch")
    private var pendingNotify: DispatchWorkItem?

    deinit {
        stopAll()
    }

    /// 幂等：已在监听的保留，新路径开始，不在列表里的停掉。
    func watch(folders: [URL]) {
        let wanted = Dictionary(folders.map { ($0.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        queue.sync {
            for path in Array(sources.keys) where wanted[path] == nil {
                stopLocked(path: path)
            }
            for path in wanted.keys where sources[path] == nil {
                startLocked(path: path)
            }
        }
    }

    func stopAll() {
        queue.sync {
            for path in Array(sources.keys) {
                stopLocked(path: path)
            }
            pendingNotify?.cancel()
            pendingNotify = nil
        }
    }

    // 以下都在 queue 上执行。

    private func startLocked(path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else {
                return
            }
            // 目录本身没了（删除、改名、卷被拔掉）：fd 指向的 vnode 已失效，先撤掉，
            // 下次对齐监听集合时若目录回来了会重新开。
            if !source.data.intersection([.delete, .rename, .revoke]).isEmpty {
                stopLocked(path: path)
            }
            scheduleNotifyLocked()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources[path] = source
    }

    private func stopLocked(path: String) {
        guard let source = sources.removeValue(forKey: path) else {
            return
        }
        source.cancel()
    }

    private func scheduleNotifyLocked() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            pendingNotify = nil
            DispatchQueue.main.async {
                self.onChange?()
            }
        }
        pendingNotify = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
