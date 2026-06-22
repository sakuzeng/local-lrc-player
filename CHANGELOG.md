# Changelog

本文件记录 Local LRC Player 的重要修改，方便后续开发时回看变更背景。

## 2026-06-15

### Added

- **菜单栏歌词**：系统状态栏显示当前歌词行（跑马灯滚动）；关闭主窗口后应用保持后台运行。
- 菜单栏歌词设置存入 SQLite `app_settings` 表：开关、最大宽度、是否显示图标。
- 数据库 schema 合并为 **v1** 基线（本地开发）；移除 v2–v4 分步迁移与 `display_settings` 表。
- 「视图」菜单与菜单栏项内可配置菜单栏歌词；点击菜单栏项可显示主窗口、播放/暂停、切歌。

### Fixed

- 菜单栏歌词使用 **NSStatusItem** 显示（参与系统布局，不覆盖系统图标）；宽度统一使用 `app_settings` 全局设置。
- 菜单栏音符图标改到歌词右侧固定显示，跑马灯文字裁剪在左侧区域，不再遮挡图标。
- 长歌词跑马灯改为单次滚动（行首→行尾→停下），换行后才重新从行首开始；状态栏宽度固定为设置值（预设 120/140/160 pt 或自定义 80–400 pt）。

- 下载当前歌词时同时搜索网易云和 QQ 音乐，在同一个候选窗口按来源分组展示结果。
- 创建原生 macOS 桌面 App：`LocalLrcPlayer.app`。
- 支持选择本地音乐目录。
- 支持扫描 `.mp3`、`.m4a`、`.flac`、`.wav`、`.aac`、`.aiff`、`.aif`。
- 支持同目录同名 `.lrc` 歌词匹配。
- 支持播放、暂停、上一首、下一首。
- 支持进度条跳转。
- 支持歌词高亮和自动滚动。
- 支持记住上次选择的音乐目录。
- 支持设置歌词来源 Cookie，并保存到本机私有配置文件。
- 支持下载当前歌曲缺失的同名 `.lrc`。
- 支持批量补全当前目录缺失的歌词。
- 支持通过当前歌词来源搜索结果自动选择最佳匹配并保存歌词。
- 支持下载当前歌词时预览候选结果并手动选择保存。
- 支持将歌词来源返回的原文和译文按同一时间戳交错输出；网易云返回英文译文时会继续追加英文译文。
- 支持重置当前歌词来源 Cookie。
- 支持 QQ 音乐作为歌词来源。
- 支持在歌词工具栏选择 `网易云` 或 `QQ音乐` 来源（用于设置 Cookie）。
- 支持为网易云和 QQ 音乐分别保存 Cookie。
- 引入本地 SQLite 数据库（`LocalLrcPlayer.sqlite`），索引音乐库、曲目元数据、播放历史与歌词下载审计。
- 支持歌曲列表搜索（歌名、歌手、专辑）。
- 支持刷新当前目录（增量 sync，无需重新选择文件夹）。
- 启动时恢复上次音乐库、选中的曲目与进度位置（不自动播放，需手动点播放）。
- 标准 macOS 菜单栏：⌘Q 退出、⌘W 关闭窗口、⌘H 隐藏、关于/帮助，以及文件/编辑/播放/窗口菜单与常用快捷键。
- 空格键切换播放/暂停（搜索框等文本输入时除外）。
- 初始化 Git 仓库与 `.gitignore`（忽略 `build/` 等构建产物）。
- 新增 `doc/` 目录：`doc/database.md` 记录 SQLite 表结构、主键/外键、索引与读写流程。
- **总播放列表（Schema v2）**：多次选择文件夹时曲目累积到系统「全部」列表；以文件内容 SHA256（`content_hash`）去重，同内容不同路径只显示一条。
- 新增 `playlists` / `playlist_tracks` / `library_tracks` / `player_state` 表；播放进度改存 `player_state`（全局，不再绑定单个库）。
- 新增 `TrackContentHasher`、`PlaylistRepository`、`PlayerStateRepository`；`test.sh` 含数据库层自动化测试。

### Changed

- 选择文件夹改为 `registerLibrary`：已注册库保留，列表展示**总播放列表**而非仅当前库。
- 刷新（⌘R）同步**所有已注册文件夹**后重载总列表。
- 状态栏/文件夹标签：多库时显示「N 个文件夹（总播放列表）」；同步摘要含「去重 N」计数。
- `LibraryRepository.activateLibrary` 更名为 `registerLibrary`。

- 将 `PlayerWindowController` 拆分为多个扩展文件，主文件只保留窗口绑定与 UI 入口：
  - `PlayerWindowController.swift` — 初始化、快捷键、Cookie、控件绑定
  - `PlayerWindowController_Library.swift` — 音乐库加载、刷新、列表查询
  - `PlayerWindowController_Playback.swift` — 播放、进度、歌词显示、会话恢复
  - `PlayerWindowController_LyricsDownload.swift` — 下载当前歌词、补全缺失歌词
- 歌曲列表仅展示歌名（有 ID3 时为「歌手 - 歌名」）及「无歌词」标记，不再显示时长；时长仍显示在底部播放进度条。
- 音乐库扫描改为增量同步：以文件 `mtime/size` 判断变更，写入 SQLite；歌词仍以同目录 `.lrc` 文件为准。
- 上次音乐目录从 `UserDefaults` 迁移到数据库 `libraries` 表。
- 补全缺失歌词改为从数据库查询 `has_lyric = 0` 的曲目；保存成功后更新索引，不全库重扫。
- 歌词下载/补全每次候选尝试写入 `lyric_download_log`；匹配打分优先使用 ID3 缓存的歌手/歌名。
- 歌词工具栏在来源下拉框前增加「Cookie 来源」标签，底部状态栏同步改为「Cookie 来源：…」，明确下拉框只用于设置/重置 Cookie。
- 下载保存歌词时会自动去掉行首的歌手名或角色前缀（如 `田翌臣: `、`合: `），只保留歌词正文。
- 将初始单文件实现拆分为多个模块：
  - `AppDelegate.swift`
  - `PlayerWindowController.swift`
  - `PlayerWindowLayout.swift`
  - `TrackListDataSource.swift`
  - `PlaybackController.swift`
  - `LyricsView.swift`
  - `SeekSlider.swift`
- 将 `main.swift` 缩减为 App 启动入口。
- 更新 `build.sh`：链接 `-lsqlite3`，并递归收集 `Sources/LocalLrcPlayer/**/*.swift`。
- 移除歌词来源 Cookie 对 Keychain 的依赖，改为本机私有配置文件，避免下载歌词时反复弹出钥匙串密码框。
- 将歌词候选结构抽象为通用 provider/candidate，复用候选预览和保存流程。
- QQ 音乐搜索和歌词详情请求改为直接使用已保存 Cookie，并从 Cookie 解析 `uin` 和 `g_tk` 请求参数。
- 歌曲列表交互：保持**双击播放**；**单击**选中；空格/播放按钮在选中行与正在播放行不同时切歌，相同时暂停/继续。
- 列表行自定义样式（关闭系统蓝色选中块）：仅选中=浅灰底+中等字重；正在播放=主题色浅底+加粗；选中且正在播放=更深主题色浅底+左侧竖条。
- `PlayerWindowController` 扩展文件命名由 `+` 改为 `_`（`PlayerWindowController_Library.swift` 等）。

### Fixed

- 修复再次打开 App 时会自动播放的问题：启动时调用 `restoreLastSelection` 仅恢复选中曲目与进度 UI，不再调用 `playTrack`；需手动点播放或按空格才会开始。
- 修复启动时搜索框自动获得焦点的问题：默认焦点给歌曲列表；点击列表、歌词区、按钮等区域时搜索框失焦。
- 修复下载当前歌词保存时提示「同名 LRC 已存在」无法替换的问题：候选窗口保存时会覆盖当前歌曲已有的 `.lrc`。
- 修复日语歌播放时歌词高亮在日文和中文之间来回切换的问题：日文原文和中文译文同时显示，高亮默认落在中文译文行。
- 修复多语种歌词有时原文和译文上下顺序不一致的问题：同一时间戳组内按原文在上、中文译文在下排列；日文歌为日文在上，英文歌为英文在上。
- 修复歌词区域空白问题：从 `NSStackView` 改为 `NSTextView` 渲染歌词。
- 修复歌词跳跃滚动问题：改为自定义平滑滚动。
- 修复 FLAC 手动拖动进度条后音频落点和歌词不一致的问题：原始 `.flac` 仍用于列表和同名 `.lrc` 匹配，实际播放时优先使用同名 `.m4a`，没有则通过 `ffmpeg` 生成 ALAC 缓存再交给 AVPlayer 播放。
- 优化拖动进度条流程：拖动时预览目标时间和歌词，松手后提交 seek，seek 完成后按播放器实际时间校准 UI；拖动前若正在播放，seek 完成后恢复播放。
- 修复歌词候选窗口卡在“正在加载歌词预览”的问题：候选窗口改为非模态显示，并为网易云歌词详情请求增加超时和降级请求。
- 修复 QQ 音乐下载歌词总是提示“未找到候选结果”的问题：旧 `client_search_cp` 搜索接口对关键词返回空列表，改用 `musicu.fcg` 的 `DoSearchForQQMusicDesktop` 搜索接口。
- 改进歌词候选匹配分：歌名从 API 混杂字段提取后再比对；歌手仅依据 API `artists` 且与本地歌手完全一致才加分。
- 修复搜索后播放再清空搜索时，总列表中丢失当前歌曲标识的问题：以 `playingTrackURL` 定位曲目，清空搜索（含搜索框 **×**）后滚动到可见行。
- 正在播放曲目改用独立列表样式（`playingTrackURL`），不依赖 `NSTableView` 选中态；点击歌词区后播放标识仍保留。
- 修复单击列表无选中反馈：`NSTableCellView` 避免文字抢点击；移除每次点击触发的整表 `reloadData`；用 `selectedTrackURL` 辅助空格切歌。

### Verified

- `./build.sh` 构建成功。
- `Info.plist` 校验通过。
- 生成的 App 可执行文件为 `arm64`。
