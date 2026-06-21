# Roadmap

本文件记录后续可以开发的方向。优先级会随着实际使用体验调整。

## Known Bugs

- 暂无已确认但未修复的问题。后续发现 bug 时先记录在这里，修复后移到 `CHANGELOG.md` 的 `Fixed`。

## High Priority

- （暂无）

## Medium Priority
- 文件夹是不是应该有删除的功能
- 播放模式：
  - 顺序播放
  - 单曲循环
  - 随机播放
- 音量控制。
- 显示当前歌曲名、歌手、总时长等更多播放信息（列表已有 ID3 时长时可优先展示在播放区）。
- 支持拖拽音乐文件夹到窗口加载。
- 多音乐库 UI：切换/管理多个已保存的音乐文件夹。

## Low Priority

- 封面显示（可复用 tracks 表 metadata，另加封面缓存字段）。
- 深色模式下的歌词颜色细化。
- 支持读取音频内嵌歌词。
- 支持歌词文件编码自动识别。
- 支持更多歌词源，例如酷狗、酷我。
- 支持覆盖已有 `.lrc` 前确认。
- 歌词下载审计 log 的查看界面。

## Technical Improvements

- 自定义播放列表 UI（系统「全部」列表已实现；用户自建列表仍待做）。
- 为 `LrcParser` 增加单元测试。
- ~~为 `MusicLibrary` / `TrackRepository` 增加扫描与增量 sync 测试。~~（`test.sh` 已覆盖总列表 sync / 去重 / 删除场景）
- 增加日志输出，方便排查播放失败和歌词匹配失败。
- 将 FLAC 转码缓存改成后台任务，避免首次播放大文件时 UI 短暂卡住。
- 曲目数量很大时（>5000）为 tracks 表增加 FTS5 全文索引。
- `TrackMetadataReader` 改用 AVAsset 异步 load API，消除 macOS 13 弃用警告。
