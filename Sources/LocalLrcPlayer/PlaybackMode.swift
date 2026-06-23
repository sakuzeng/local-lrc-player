import Foundation

enum PlaybackMode: String, CaseIterable {
    case sequential
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .sequential:
            return "顺序播放"
        case .repeatOne:
            return "单曲循环"
        case .shuffle:
            return "随机播放"
        }
    }

    var symbolName: String {
        switch self {
        case .sequential:
            return "arrow.right.to.line"
        case .repeatOne:
            return "repeat.1"
        case .shuffle:
            return "shuffle"
        }
    }

    func next() -> PlaybackMode {
        switch self {
        case .sequential:
            return .repeatOne
        case .repeatOne:
            return .shuffle
        case .shuffle:
            return .sequential
        }
    }
}
