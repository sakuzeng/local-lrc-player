# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

一个轻量的原生 macOS 音乐播放器(AppKit,不用 SwiftUI),播放本地音频并显示同名
`.lrc` 同步歌词。界面文案和大部分文档都是中文。

## 构建与运行

没有 Xcode 工程,也没有 SwiftPM 依赖图 —— 源码直接用 `swiftc` 编译并链接系统
`sqlite3`。`Package.swift` 只声明了一个 `library` target,基本是空壳;不要依赖
`swift build` / `swift test`。

```bash
./build.sh                 # 编译 + 打包 build/LocalLrcPlayer.app,临时签名
open build/LocalLrcPlayer.app
./test.sh                  # 编译并运行测试二进制,然后再调用 build.sh
```

- `build.sh` 自动按字母序收集 `Sources/LocalLrcPlayer/**/*.swift` ——
  新增 Swift 文件无需改任何文件清单。 `main.swift` 是 App 入口,App 构建会包含它,
  测试构建会排除它。
- 构建用 `-O`。改动后必须退出正在运行的 App、重新构建、再打开 —— 没有热重载。
- FLAC 的 seek 精度依赖 `/opt/homebrew/bin/ffmpeg`(转码成 ALAC 缓存,放在
  `~/Library/Caches/LocalLrcPlayer/Transcoded`)。

## 测试

测试是手写的 harness,不是 XCTest。`Tests/RunDatabaseTests/main.swift` 自己定义了
`assertEqual` / `assertTrue`,文件末尾用 `do { ... } catch { exit(1) }` 作为 runner;
`test.sh` 把所有源文件(去掉 `main.swift`)和这个测试文件一起编译成一个二进制再运行。
没有单测运行器 —— 想只跑某一个测试,就把末尾 `do` 块里的其他调用注释掉。
`Tests/LocalLrcPlayerTests/` 和 `Sources/LocalLrcPlayerApp/` 是空占位目录,未使用。

测试聚焦在最容易坏、又最难肉眼发现的 SQLite 仓储逻辑:跨库的内容哈希去重、
总播放列表的累积/排序、播放状态的持久化与删库时清空、设置项/迁移的默认值。

## 架构

数据层(SQLite,索引的唯一真相来源)。 `AppDatabase` 持有连接并执行 schema 迁移
(当前 v6),数据库在 `~/Library/Application Support/LocalLrcPlayer/LocalLrcPlayer.sqlite`。
每张表都有专门的 repository(`LibraryRepository`、`TrackRepository`、
`PlaylistRepository`、`PlayerStateRepository`、`AppSettingsRepository`、
`PlayHistoryRepository`、`LyricLogRepository`);记录结构体在 `DatabaseModels`。
关键不变量:曲目按 SHA256 内容哈希去重(`TrackContentHasher`),所以同一段音频出现在两个
文件夹里只会是总播放列表中的一行。schema 与读写流程见 `doc/database.md`。
数据库只做索引;歌词和音频始终是用户所选文件夹里的文件 —— 音频旁边的 `.lrc` 才是
真相,数据库不是第二份歌词。

窗口控制器(按职责拆成多个 extension)。 `PlayerWindowController` 是主窗口,它的行为
分散在 `PlayerWindowController_Library`(加载/刷新)、`_Playback`(播放、进度、歌词同步、
播放模式)、`_LyricsDownload` 里。`PlayerWindowLayout` 搭建布局,`TrackListDataSource`
驱动曲目表格与播放行样式,`LyricsView` 负责歌词的渲染/滚动/高亮。
`SettingsWindowController` 是 ⌘, 设置窗口。

播放。 `PlaybackController` 封装 `AVPlayer`;`PlaybackAssetResolver` 处理
FLAC→ALAC 的转码缓存路径;`SeekSlider` 是自定义进度条,带「先预览、松手再 seek」的行为;
`PlaybackMode` 是顺序/单曲循环/随机的枚举(持久化)。

歌词下载(两个来源)。 `NetEaseLyricClient` 和 `QQMusicLyricClient` 分别请求各自的
Web API(各需自己的 Cookie,由 `CookieStore` 以明文文件保存,不是 Keychain)。
`LyricSearchService` 协调搜索 + 评分 + 补全缺失歌词的流程;`LyricCandidateDialog` 是
手动预览/选择的 UI;`LyricFormatter` 合并原文 + 译文行;`LyricFileWriter` 写出同名
`.lrc`。评分时歌手只认 API 的 `artists` 字段。

菜单栏歌词。 `MenuBarLyricsController` 在窗口关闭后仍持续显示当前行;
`MenuBarLyricsStatusImage` 渲染滚动位图;`MenuBarStatusItemVisibility` /
`MenuBarVisibilityGuide` 处理 macOS 26 的菜单栏可见性权限。`MenuBarLyricsView` 是遗留代码。

音乐库访问。 音乐文件夹可能位于 macOS 受保护目录(如「下载」);
`LibraryBookmarkStore` 持久化 Security-Scoped Bookmark,使授权在重启后仍有效。

## 需要同步维护的文档

`CHANGELOG.md`(按日期记录已完成工作)、`ROADMAP.md`(计划 + 已知 bug)、
`HANDOFF.md`(跨工具交接 + 验证清单)、`doc/database.md`、`doc/ui.md`。README 与这些文档
详尽且为最新 —— 在反推行为之前先查它们。
