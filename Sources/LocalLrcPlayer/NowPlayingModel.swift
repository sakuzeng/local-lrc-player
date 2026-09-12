import AppKit

/// 播放态的唯一真相（主线程）。写入方只有 PlayerWindowController；菜单栏卡片这类消费者
/// 读 snapshot、订阅变化，想控制播放就调 commands，不再反向拿着窗口控制器。
/// 系统「正在播放」（NowPlayingCenter）仍由控制器直接喂：封面宽限、play() 后 waiting 期的
/// isPlaying 覆盖都是写入侧的细节，放这里会把 model 变成第二个控制器。
final class NowPlayingModel {
    struct Commands {
        var togglePlayPause: () -> Void = {}
        var next: () -> Void = {}
        var previous: () -> Void = {}
        var cycleMode: () -> Void = {}
        /// 进度分数 0...1。
        var seek: (Double) -> Void = { _ in }
        /// 音量 0...1。
        var setVolume: (Double) -> Void = { _ in }
    }

    /// 订阅凭证：释放或 cancel() 即退订。
    final class Observation {
        private let onCancel: () -> Void

        init(onCancel: @escaping () -> Void) {
            self.onCancel = onCancel
        }

        func cancel() {
            onCancel()
        }

        deinit {
            onCancel()
        }
    }

    private(set) var snapshot: NowPlayingSnapshot?
    var commands = Commands()
    private var observers: [UUID: (NowPlayingSnapshot?) -> Void] = [:]

    /// 控制器在切歌、播放/暂停、seek 完成和 0.2s tick 上调；nil 表示没有曲目。
    func publish(_ snapshot: NowPlayingSnapshot?) {
        self.snapshot = snapshot
        for observer in observers.values {
            observer(snapshot)
        }
    }

    func observe(_ handler: @escaping (NowPlayingSnapshot?) -> Void) -> Observation {
        let id = UUID()
        observers[id] = handler
        return Observation { [weak self] in
            self?.observers[id] = nil
        }
    }
}
