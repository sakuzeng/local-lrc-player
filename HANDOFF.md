# Handoff Guide

本文件用于在不同 AI 工具或开发者之间交接 Local LRC Player 的开发上下文。

## Current State

更新时间：2026-06-23

项目路径：

```text
/Users/sakuzeng/improve/coding/mac_app/local-lrc-player
```

当前项目是一个原生 macOS 本地 LRC 播放器：

- 语言和框架：Swift + AppKit + AVFoundation。
- 构建方式：不使用 Xcode 工程；`./build.sh` 通过 `swiftc` 生成 `.app`；`./test.sh` 运行数据库测试并构建。
- 构建产物：`build/LocalLrcPlayer.app`。
- 目标平台：macOS。

当前已实现功能：

- 选择本地音乐文件夹可**多次累积**到总播放列表；同文件内容（SHA256）自动去重。
- SQLite schema **v1** 基线 + **v2** 主窗口 frame + **v3** `playback_mode`；播放进度与模式存 `player_state`。
- **菜单栏歌词**：`NSStatusItem` 显示当前行；短句静止、长句跑马灯；宽度读 `app_settings` 全局设置；关窗不退出，后台继续更新。
- **设置窗口**（⌘,）：音乐库列表（添加/移除文件夹）、歌词 Cookie 与下载、菜单栏歌词配置；打开时居中到主窗口所在屏幕，并滚回顶部显示「音乐库」。
- 主窗口 **NSToolbar**：选择文件夹、刷新、搜索；Cookie/歌词工具已移入设置。
- 主窗口**毛玻璃质感**：透明标题栏 + unified 工具栏 + `NSVisualEffectView` 背景；列表/歌词无边框。
- 底部**图标化播放控制**与自定义进度条（`PlayerWindowLayout` / `SeekSlider`）。
- **歌词区**：距离渐变淡出、当前行主题色高亮与换行动画；动态上下留白使首尾行可居中显示（`LyricsView`）。
- **曲目列表**：双行单元格（歌名 + 歌手/专辑）；`歌手 - 歌名` 解析；`TrackTableView` 集中管理悬停；播放行主题色浅底（`TrackListDataSource`）。
- **空状态**：列表/歌词无内容时 SF Symbol 占位（`UIChrome` / `EmptyStateView`）；主窗口仍为平铺毛玻璃布局。
- 启动时恢复上次主窗口位置与大小（`player_state.window_*`）；无记录时居中显示。
- **播放模式**：顺序 / 单曲循环 / 随机；三种模式按钮均主题色高亮；偏好存 `player_state.playback_mode`（schema v3）；随机 `shuffleHistory`；顺序末首回第一首。
- **列表顶栏**：`歌曲 · N` + 定位正在播放（`scope`）；`listNavigationStack` 可扩展（左侧标题日后可换播放列表名）。详见 `doc/ui.md`。
- 菜单栏项 / 「视图」菜单可配置菜单栏歌词；设置窗口亦可配置并写入 `app_settings`。
- 启动时 sync 所有已注册库；⌘R 刷新全部库。
- 数据库记住上次曲目与播放进度；再次打开时恢复选中状态和进度位置，**不自动播放**。
- 双击播放，支持播放/暂停、上一首、下一首、进度条 seek；**空格**切换播放/暂停（搜索框输入时除外）。
- 标准 macOS 菜单栏（⌘Q 退出、⌘O 选文件夹、⌘R 刷新、⌘, 设置等），见 `AppMenuBuilder.swift`。
- 读取同目录同名 `.lrc`，显示同步歌词，高亮当前行并平滑滚动。
- FLAC 播放时优先使用同名 `.m4a`；没有同名 `.m4a` 时，通过 `/opt/homebrew/bin/ffmpeg` 转成 ALAC `.m4a` 缓存后播放。
- ALAC 缓存目录：`~/Library/Caches/LocalLrcPlayer/Transcoded`。
- 支持网易云和 QQ 音乐作为歌词来源。
- 网易云和 QQ 音乐都使用 Cookie，请求前需要在 App 内设置对应来源 Cookie。
- Cookie 保存到本机配置文件，不再使用 Keychain：
  - `~/Library/Application Support/LocalLrcPlayer/netease-cookie.txt`
  - `~/Library/Application Support/LocalLrcPlayer/qqmusic-cookie.txt`
- 下载当前歌词时，同时搜索已设置 Cookie 的网易云和 QQ 音乐，在同一个候选窗口按来源分组展示。
- 下载当前歌词会弹出候选窗口，支持预览和手动选择保存。
- 歌词候选匹配分已改进：歌名规范化后比对，歌手仅认 API `artists` 且完全一致才加分。
- 补全缺失歌词时，同时搜索已设置 Cookie 的网易云和 QQ 音乐，按匹配分从高到低自动尝试并保存。
- 下载歌词只写入缺失的同名 `.lrc`，不覆盖已有 `.lrc`。
- 多语种歌词会按同一时间戳交错输出原文和译文；网易云返回英文译文时继续追加英文译文。
- 播放时日文/英文原文和中文译文会同时显示，顺序固定为原文在上、中文译文在下；高亮默认落在中文译文行。
- 歌曲列表支持搜索（歌名、歌手、专辑）；「刷新」按钮增量 sync 全部已注册文件夹。
- 正在播放曲目在列表中以自定义行样式标识（`playingTrackURL` / `TrackRowView`）：浅灰=仅选中、主题色浅底=播放中；双行显示歌名与歌手/专辑；搜索取消后仍定位到总列表对应行。
- 关闭主窗口后应用不退出（`applicationShouldTerminateAfterLastWindowClosed = false`），菜单栏歌词继续更新；⌘Q 或 Dock 可完全退出。
- 搜索框启动时不自动获得焦点；点击其他区域时失焦，避免误输入。
- 本地 SQLite 索引音乐库与曲目；启动恢复上次库、选中曲目与进度位置（不自动播放）。
- 歌词下载/补全尝试写入 `lyric_download_log` 审计表。
- 已初始化 Git 仓库；`.gitignore` 忽略 `build/` 与 `.DS_Store`。
- 项目根目录 `doc/` 文档：数据库 schema（`doc/database.md`）、主窗口 UI 与工具栏约定（`doc/ui.md`）。

最近关键修复和设计决策：

- **设置窗口**（2026-06-23）：`SettingsWindowController` 替代工具栏弹出面板；`LibraryRepository.deleteLibrary` / `TrackRepository.removeLibrary` 处理整库移除与数据库清理。
- **播放焦点**（2026-06-23）：`userSelectedTrackIndex` 区分用户点选与程序高亮，修复顺序播放后空格误播第一首。
- **多显示器**（2026-06-23）：设置窗口 `positionOnActiveScreen()` 跟随主播放窗口屏幕，避免 ⌘, 跑到外接主屏。
- **设置滚动**（2026-06-23）：翻转文档坐标 + `scrollContentToTop()`，首次 ⌘, 不再默认停在「歌词」区块。
- **窗口质感**（2026-06-23）：`fullSizeContentView`、unified 工具栏、毛玻璃背景；内容区对齐 safe area。
- **播放区 UI + seek**（2026-06-23）：SF Symbol 播放控制、自定义 `SeekSlider`；修复拖动/启动时歌词不同步、未播放时拖动无效、圆点与轨道对齐等问题（`PlayerWindowController_Playback`、`LyricsView.updateWhenReady`、`completeSliderSeek`）。
- **歌词区美化**（2026-06-23）：`LyricsView` 按行距渐变字号/透明度、换行平滑过渡；`textContainerInset` 动态半屏留白修复末行高亮贴底；未使用边缘毛玻璃遮罩。
- **曲目列表**（2026-06-23）：`TrackTableCellView` 双行布局；`歌手 - 歌名` 拆分；悬停由 `TrackTableView` + `TrackListDataSource.hoveredRow` 统一管理，修复滚动时灰底残影。
- **空状态 + 窗口**（2026-06-23）：`EmptyStateView` 图标占位；主窗口保持平铺毛玻璃（卡片/侧栏方案已回退）；`player_state` v2 记忆主窗口 frame。
- **播放模式 + 定位**（2026-06-23）：`PlaybackMode`、`listHeaderBar`；定位放列表顶栏（工具栏不宜拆 pill，见 `doc/ui.md`）；顺序模式按钮高亮已修复。
- `main.swift` 已拆分成多个职责模块，主协调逻辑在 `PlayerWindowController.swift`。
- 为避免 macOS 钥匙串反复弹密码，Cookie 存储从 Keychain 改为本机私有配置文件。
- FLAC 手动拖动进度条后歌词和音频不同步，根因是 AVPlayer 直接 seek FLAC 落点不准；当前通过 ALAC 缓存规避。
- QQ 音乐旧搜索接口 `client_search_cp` 会返回空候选，已改用 `musicu.fcg` 的 `DoSearchForQQMusicDesktop`。
- **QQ 音乐搜索再次空候选**（2026-06-23）：迁移到 `musicu.fcg` 时在请求里附带 `comm.ct=24&cv=0`（模拟桌面客户端）；QQ 音乐上游后来对该参数组合改为返回 `code:0` 但 `song.list` 为空（静默失败，非 App 近期 UI 改动引起）。搜索请求已去掉 `comm` 字段；歌词拉取接口不受影响。
- 歌词候选窗口曾经卡在“正在加载歌词预览”，已改为非模态窗口，并为网易云歌词详情请求增加超时和降级请求。
- 日语歌播放时中日文高亮来回切换，已在 `LrcParser.activeLineIndex` 中让同一时间戳组内优先高亮中文译文，日文原文仍保留显示。
- 多语种歌词显示顺序不一致，已在 `LrcParser.normalizedDisplayOrder` 中按组内语言组合固定为原文在上、中文译文在下；日文歌为日文在上，英文歌为英文在上。
- 下载保存歌词时会去掉行首歌手名/角色前缀（如 `田翌臣: `、`合: `），在 `LyricFormatter.stripSingerPrefix` 中处理。
- 下载当前歌词双源搜索已在 `LyricSearchService.searchAllCandidates` 和 `LyricCandidateDialog` 中实现，按网易云/QQ 音乐分组展示候选。
- 下载当前歌词保存时会覆盖已有同名 `.lrc`；补全缺失歌词仍只写入缺失文件。
- 补全缺失歌词时，已设置 Cookie 的网易云和 QQ 音乐会合并候选，按匹配分依次尝试直到成功返回歌词；见 `LyricSearchService.downloadBestAvailableLyric`。
- 引入 SQLite（`AppDatabase.swift` + Repository 层）：音乐库/曲目索引、播放历史、歌词审计；歌词文件仍以磁盘 `.lrc` 为准。
- 上次目录从 UserDefaults 迁移到 `libraries` 表；`TrackRepository.sync` 做增量扫描。
- 启动恢复曾误用 `playTrack` 导致自动播放，已改为 `restoreLastSelection` + `restoredPlaybackPosition`，按播放时才 `playTrack(..., startFromSavedPosition: true)`。
- `PlayerWindowController` 已拆分为 `_Library` / `_Playback` / `_LyricsDownload` 扩展文件；空格键通过 `installKeyboardMonitor` 全局监听（文本输入焦点时跳过）。
- 列表行样式：`TrackRowView` 自定义绘制（`selectionHighlightStyle = .none`）；`playingTrackURL` + `selectedTrackURL`；`updatePlayingTrackInList` 在搜索清空/重载时按路径匹配并滚动。

当前主要源码文件：

```text
Sources/LocalLrcPlayer/
  AppDatabase.swift             SQLite 连接与 schema 迁移（v3）
  PlaybackMode.swift            播放模式
  TrackContentHasher.swift      文件 SHA256
  PlaylistRepository.swift      总播放列表
  PlayerStateRepository.swift   播放进度、窗口 frame、播放模式
  LibraryRepository.swift       registerLibrary / deleteLibrary / allLibraries
  TrackRepository.swift         sync、removeLibrary（内容去重）
  AppSettingsRepository.swift   菜单栏歌词等 UI 设置（app_settings）
  SettingsWindowController.swift  设置窗口（⌘,）：音乐库/歌词/菜单栏
  PlayerWindowToolbar.swift     主窗口 NSToolbar
  UIChrome.swift                空状态、Symbol 工具
  MenuBarLyricsController.swift 系统菜单栏歌词与快捷菜单
  MenuBarLyricsView.swift       菜单栏跑马灯歌词绘制
  LyricLogRepository.swift      歌词下载审计
  TrackMetadataReader.swift     AVAsset 读取 ID3 元数据
  DatabaseModels.swift          数据库记录模型
  AppDelegate.swift             应用生命周期、设置/About/Help
  AppMenuBuilder.swift          标准 macOS 菜单栏与快捷键
  main.swift                    App 启动入口
  PlayerWindowController.swift  主窗口：绑定、Cookie、快捷键、焦点
  PlayerWindowController_Library.swift      音乐库加载、刷新、移除后重载
  PlayerWindowController_Playback.swift     播放、进度、歌词显示
  PlayerWindowController_LyricsDownload.swift  歌词下载与补全
  PlayerWindowLayout.swift      主窗口 UI 布局
  TrackListDataSource.swift     左侧歌曲列表、正在播放行样式、userSelectedTrackIndex
  PlaybackController.swift      AVPlayer 播放封装
  PlaybackAssetResolver.swift   FLAC 播放资源解析和 ALAC 缓存生成
  LyricsView.swift              歌词显示、高亮、滚动
  LrcParser.swift               LRC 解析
  MusicLibrary.swift            音乐目录扫描
  SeekSlider.swift              进度条拖动状态
  CookieStore.swift             歌词来源 Cookie 本地保存
  NetEaseLyricClient.swift      网易云搜索和歌词接口
  QQMusicLyricClient.swift      QQ 音乐搜索和歌词接口
  LyricSearchService.swift      歌词搜索、候选评分和下载协调
  LyricCandidateDialog.swift    候选歌词预览和选择窗口
  LyricFormatter.swift          原文、译文、英文译文交错输出
  LyricFileWriter.swift          同名 .lrc 写入
  Result+Success.swift          Result 便捷扩展
```

最近一次本地验证：

- `./test.sh`：通过（数据库测试 + 构建）。
- `./build.sh`：通过。
- `plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist`：通过。
- 生成的可执行文件：`Mach-O 64-bit executable arm64`。

## Opening Prompt

将下面这段作为新工具的开场提示词：

```text
请先阅读这个项目的 README.md、CHANGELOG.md、ROADMAP.md、HANDOFF.md，以及 doc/database.md（数据库）和 doc/ui.md（主窗口 UI），然后再查看 Sources/LocalLrcPlayer 下的代码。

项目路径：
/Users/sakuzeng/improve/coding/mac_app/local-lrc-player

这是一个原生 macOS 本地 LRC 播放器，使用 Swift + AppKit + AVFoundation，不使用 Electron、Node、Rust、Xcode 工程或 Swift Package。构建方式是运行 ./build.sh，通过 swiftc 生成 build/LocalLrcPlayer.app。

开发要求：
1. 保持现有技术栈和构建方式不变。
2. 修改前先理解 README/CHANGELOG/ROADMAP/HANDOFF 中记录的当前功能、已修复问题、后续计划和交接要求。
3. 新功能或 bug 修复完成后，必须更新对应文档：
   - README.md：当前真实功能、使用方式、限制。
   - CHANGELOG.md：已经完成的修改，放到对应日期的 Added/Changed/Fixed/Verified。
   - ROADMAP.md：未完成的计划或已知 bug。
   - HANDOFF.md：如果交接流程或协作规则发生变化，再更新本文件。
4. 不要删除或覆盖已有本地音乐、歌词、Cookie、缓存文件。
5. 修改后运行：
   cd /Users/sakuzeng/improve/coding/mac_app/local-lrc-player
   ./build.sh
   plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist
6. 完成后请更新 HANDOFF.md 的 Current State，并按 Handoff Template 输出交接记录，方便切回其他工具继续开发。
```

## Handoff Template

开发完成后，请输出下面格式的交接记录：

```text
## Handoff

项目路径：
/Users/sakuzeng/improve/coding/mac_app/local-lrc-player

本次目标：
...

修改文件：
- ...

实现内容：
- ...

验证：
- ./build.sh：通过/失败，失败原因
- plutil：通过/失败，失败原因
- 手动测试：...

文档更新：
- README.md：...
- CHANGELOG.md：...
- ROADMAP.md：...
- HANDOFF.md：...

未完成/风险：
- ...
```

## Return Workflow

如果另一个 AI 工具完成开发后要切回当前工具，请让它做两件事：

1. 更新本文件的 `Current State`，写清楚最新功能、关键改动、验证结果和未完成风险。
2. 在对话末尾按 `Handoff Template` 输出交接记录。

切回当前工具时，可以直接粘贴它输出的 `Handoff` 记录，并说明“请基于 HANDOFF.md 和这段交接记录继续开发”。

## Documentation Rules

- 当前真实功能和使用方式写入 `README.md`。
- 已完成的修改写入 `CHANGELOG.md`。
- 之后要做的功能、已知但未修的 bug 写入 `ROADMAP.md`。
- SQLite 表结构、主键/外键、读写流程写入 `doc/database.md`；主窗口 UI 与工具栏约定写入 `doc/ui.md`；索引见 `doc/README.md`。
- 跨工具协作流程、开场提示词、交接模板写入 `HANDOFF.md`。
- 修复 bug 后，将对应条目从 `ROADMAP.md` 的 `Known Bugs` 移到 `CHANGELOG.md` 的 `Fixed`。

## Verification Checklist

每次代码修改后至少执行：

```bash
cd /Users/sakuzeng/improve/coding/mac_app/local-lrc-player
./build.sh
plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist
```

如果修改了播放、歌词显示、下载歌词或文件扫描逻辑，还需要做对应手动测试，并在交接记录中写清楚测试结果。
