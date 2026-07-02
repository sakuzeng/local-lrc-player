# Changelog

本文件记录 Local LRC Player 的重要修改，方便后续开发时回看变更背景。

## 2026-07-02

本日:修复菜单栏歌词末字被切;代码组织重构(清理遗留代码、按职责拆分过大的仓储文件)。

### Fixed

- 菜单栏歌词撑满滚动到末尾时最后一个字右侧被切掉:`textAreaWidth` 右侧留白从 8pt 增到 8+6pt,使末字测量右缘从 `maxWidth-2` 内缩到 `maxWidth-8`,落进位图裁剪区(右缘 `maxWidth-4`)内部,避免字形墨迹超出 advance 宽度被剃掉。

### Changed

- 删除遗留死代码 `MenuBarLyricsView.swift`（全项目零引用，菜单栏歌词已由 `MenuBarLyricsController` + `MenuBarLyricsStatusImage` 承担）。
- 拆分 `TrackRepository`（原 636 行）：扫描 + 增量 sync 引擎移入新文件 `TrackRepository_Sync.swift`（`sync` / `syncAll` + sync 专属助手 + `TrackSyncSummary`），主文件仅保留查询 / CRUD / `removeLibrary` 与两者共享的底层写入助手。对外接口与调用点不变，`test.sh` 无需改动。因 Swift `private` 为文件级作用域，`database` / `playlistRepository` 及被 sync 复用的助手放宽为 internal。

## 2026-06-23

本日主要交付：主窗口 UI 美化（工具栏/毛玻璃/播放区/歌词/列表）、设置窗口、空状态与窗口记忆、播放模式（schema v3）、列表顶栏定位、`doc/ui.md` 工具栏经验文档。

### Added

- 设置窗口（`SettingsWindowController`）：应用菜单 设置… 或 ⌘, 打开；收纳音乐库管理、歌词 Cookie/下载、菜单栏歌词配置。
- 设置中可移除已注册音乐文件夹（不删除磁盘文件）；`LibraryRepository.deleteLibrary` + `TrackRepository.removeLibrary` 清理 `library_tracks`、孤儿 `tracks`、`playlist_tracks`，并在需要时重定向 `tracks.library_id` / 规范路径。
- 主窗口 NSToolbar（`PlayerWindowToolbar`）：选择文件夹、刷新、搜索；主内容区仅保留列表、歌词与播放控制。
- 主窗口窗口质感：`fullSizeContentView` + 透明标题栏 + `toolbarStyle = .unified`；全窗口 `NSVisualEffectView`（`.underWindowBackground`）毛玻璃背景。
- 数据库测试：`testRemovingLibraryKeepsSharedTrack`、`testRemovingLibraryClearsPlayerState`。
- 数据库 schema v2：`player_state` 增加主窗口位置/大小列（v1 库自动迁移）。
- 播放模式：顺序 / 单曲循环 / 随机；播放区按钮循环切换（`arrow.right.to.line` / `repeat.1` / `shuffle`），写入 `player_state.playback_mode`（schema v3）。
- 数据库 schema v3：`player_state` 增加 `playback_mode` 列。
- 列表顶栏定位：曲目列表上方 `listHeaderBar`（`歌曲 · N` + `scope` 定位正在播放）；`listNavigationStack` 预留扩展位。
- 数据库测试：`PlayerStateRepositoryTests`（`playback_mode` 默认值与持久化）；`testSyncReordersMasterPlaylistByFileName`。
- 文档：`doc/ui.md`（主窗口布局与 NSToolbar 分段经验）。

### Changed

- Cookie 来源、设置/重置 Cookie、下载当前歌词、补全缺失歌词从工具栏弹出面板移至设置窗口。
- 设置界面采用分组卡片 + 表单行布局（音乐库 / 歌词 / 菜单栏歌词三块统一风格）。
- 移除主窗口 `lyricToolsPanel` 及工具栏「⋯」歌词工具按钮。
- 主窗口列表与歌词区去掉硬边框，内容对齐 `safeAreaLayoutGuide`；列表 / 歌词视图背景透明，靠 `NSSplitView` 细分割线与毛玻璃区分区域。
- 底部播放控制改为 SF Symbol 图标（上一首 / 播放·暂停 / 下一首），主播放键圆形强调样式；`SeekSlider` 自定义细圆角轨道与主题色圆点滑块（悬停略放大）。
- 进度条 seek 与歌词预览逻辑重构：`commitProgressSeek` 结算等待播放器落点、`resolvedPlaybackDuration` 在未播放时回退 ID3/文件时长；启动恢复与点播放前拖动进度条均即时定位歌词（`LyricsView.updateWhenReady`）。
- 歌词区美化（`LyricsView`）：非当前行按与当前行距离渐变字号/透明度；当前行 22pt 主题色加粗，换行时约 0.28s 颜色与字号平滑过渡；上下动态留白（约半屏）使首尾歌词也能滚到视口正中。
- 曲目列表双行展示（`TrackTableCellView` / `TrackTableView`）：歌名主标题 + 歌手/专辑次标题（48pt 行高）；优先解析「歌手 - 歌名」文件名或合并标题，ID3 分字段时直接用标签；播放行主题色浅底与加粗歌名（无喇叭图标）。
- 空状态占位（`EmptyStateView` / `UIChrome`）：列表与歌词区无内容时显示 SF Symbol + 标题/副标题；主窗口布局保持平铺毛玻璃（未采用卡片分组）。
- 主窗口位置记忆：`player_state` 表 v2 增加 `window_*` 四列；启动恢复上次 frame，无记录时居中；拖动/缩放与关窗时写入。
- 底部播放控制增加播放模式按钮（顺序 / 单曲循环 / 随机）；曲目结束与上一首/下一首按模式切换；随机模式维护播放历史以支持「上一首」回退。
- 顺序播放：末首自然结束后从列表第一首继续，不再停在末尾。
- 定位正在播放：经工具栏多方案验证后，最终放在列表顶栏 `listNavigationStack`（`scope`）；搜索过滤时先清空搜索再滚动定位。

### Fixed

- 顺序播放自动切歌后，空格/菜单栏误作用于列表第一首：`TrackListDataSource.userSelectedTrackIndex` 与 `playTrack` 同步选中行。
- 菜单栏歌词：连续两行相同文字时第二行不再卡在已滚完状态。
- 设置窗口 ⌘, 打开时居中到主播放窗口所在屏幕（不再固定到系统主显示器）。
- 首次 ⌘, 打开设置时滚动区域停在中间、看不到顶部「音乐库」：文档视图改为翻转坐标，每次打开时 `scrollContentToTop()` 滚回顶部。
- 进度条拖动后歌词错位：移除 `progressChanged` 松手时的重复 seek；seek 完成前阻止 `tick()` 用旧 `currentTime` 覆盖；结算超时仍用滑块目标时间而非滞后播放器时间。
- 未播放时拖动进度条无效：无 AVPlayer 时用曲目时长预览，松手后更新 `restoredPlaybackPosition` 与数据库，点播放从拖动位置开始。
- 启动/点播放后歌词停在开头：`loadLyrics` 支持 `highlightAt`，`render` 不再强制滚顶，布局就绪后 `updateWhenReady` 定位；时长缺失时从音频文件读取。
- 进度条圆点与轨道：圆点垂直居中对齐自定义轨道；拖动时整控件重绘避免透明背景残影；已播放段延伸至圆点中心，消除从头播放时的空隙。
- 歌曲末尾歌词贴底：歌词区上下留白随视口高度调整，末行高亮可保持在视口正中而非被 `maxY` 卡在底部。
- 列表悬停滚动残影：悬停状态改由 `TrackListDataSource` 集中管理；`TrackTableView` 监听鼠标移动，滚动时按当前指针重算悬停行，避免行复用后多行灰底残留。
- 顺序播放模式按钮不高亮：`setPlaybackMode` 对三种模式统一使用 `controlAccentColor`，不再将顺序模式降为次要色。
- 刷新后列表排序不更新：每次 `TrackRepository.sync` 结束后重算总播放列表 `sort_order`（先按 `library_id`，再按列表显示名自然排序；见 2026-06-25 条目）。
- 歌词下载时 Cookie 按钮变灰且无法恢复：下载进行中仅禁用下载类按钮；切换 Cookie 来源或重新打开设置会刷新状态；关闭候选窗口（含点 ×）会正确恢复按钮。
- 下载当前歌词只显示单一来源：已配置双 Cookie 时候选对话框始终按网易云 / QQ 音乐分组展示（某来源无结果时仍显示对应分组标题）。
- QQ 音乐搜索始终返回空候选：2026-06-15 从 `client_search_cp` 迁到 `musicu.fcg` 时，请求附带 `comm.ct=24&cv=0`（模拟桌面客户端）；QQ 音乐上游后来对该参数改为 HTTP 200 + `code:0` 但 `song.list` 为空（静默失败，与近期 UI/设置改动无关）。已移除搜索请求中的 `comm` 字段；双源候选与歌词预览恢复正常。

### Verified

- `./build.sh` 构建成功。
- `./test.sh` 全部通过（含 `PlayerStateRepositoryTests`）。

## 2026-06-25

本日主要交付：底部播放区布局重构（传输/进度分列对齐歌词）、播放控制视觉统一、总列表排序规则改进。

### Changed

- 底部播放区：传输控制（上一首/播放/下一首 + 播放模式 pill）放在列表列底栏 `transportBar`；进度条 + 时间放在歌词列底栏 `progressBar`，左右 28pt 与歌词 `textContainerInset` 对齐。
- 传输控制视觉：上一首/播放/下一首共用同一 `quaternarySystemFill` pill，取消播放键单独圆形主题色底；三键统一 32×32 无边框图标样式。
- 播放模式按钮：独立 pill（与传输组间距 20pt）；顺序模式图标改为 `arrow.right.to.line.compact`；当前模式统一用 SF Symbol 分层主题色高亮。
- 总列表排序（刷新后生效）：先按音乐库注册顺序（`library_id`），同库内按列表显示名（优先 ID3「歌手 - 歌名」，否则文件名）做 macOS 自然排序（`localizedStandardCompare`），替代原先仅按 `file_name` + SQLite `NOCASE` 排序。

### Fixed

- 启动即崩溃：底部栏曾用 `widthAnchor` 跨 split 绑定列表列宽，与 `NSSplitView` 列宽约束冲突导致 Auto Layout 异常；已改为底栏放入各自 split 子视图。
- 列表排序与显示不一致：列表展示 ID3 歌手/歌名，旧排序只按原始文件名且中文等字符在 SQLite `NOCASE` 下与 Finder 自然顺序不同；已统一排序键与展示逻辑。
- 顺序播放模式不高亮：播放模式 pill 美化后顺序模式误用次要色；三种模式当前态均用主题色。
- 重启后进度时间显示 00:00 / 00:00：未加载 AVPlayer 时 `tick()` 覆盖会话恢复的时间标签；改为 `refreshIdlePlaybackDisplay` 用已选曲目时长与上次进度预览。

### Verified

- `./build.sh` 构建成功。
- `./test.sh` 全部通过。

## 2026-06-25（菜单栏歌词）

本日主要交付：macOS 26 菜单栏歌词显示修复、滚动/对齐/样式改进、音乐库 Security-Scoped Bookmark。

### Added

- `MenuBarLyricsStatusImage`：菜单栏歌词改为位图渲染（白字、短句居中），兼容 macOS 26 上 `button.title` 不显示的问题。
- `MenuBarStatusItemVisibility`：启动前清除 `NSStatusItem Visible` / `VisibleCC` 等持久化隐藏状态，并多次强制 `isVisible = true`。
- `MenuBarVisibilityGuide`：检测菜单栏项可能被系统拦截时，提示打开「系统设置 → 菜单栏」。
- `LibraryBookmarkStore`：音乐库文件夹 Security-Scoped Bookmark；启动时恢复授权，减少「下载」等受保护目录每次启动弹窗。

### Changed

- 菜单栏宽度：设置中的 120/140/160 pt 等为最大宽度；短歌词时 pill 随文字收缩，长句滚动时扩至上限。
- 菜单栏滚动：长句播放时从行首滚到行尾后停下（不再循环）；换行后重新从行首开始。
- 菜单栏下拉菜单：使用 `statusItem.menu` 原生绑定（无 `popUp` 顶部 `^` 拖拽柄）；菜单外观设为浅色（`NSAppearance.aqua`）。
- 构建标识：`CFBundleIdentifier` 改为 `local.lrc.player.v2`（绕过 macOS 26 对旧 bundle 的菜单栏项卡住状态；需在系统设置中重新允许菜单栏显示）。

### Fixed

- 菜单栏歌词完全不显示（macOS 26）：启动时 `menuBarLyricsController` 尚未注入导致 `syncMenuBarLyrics` 跳过；`AppDelegate` 就绪后补同步；`restoreLastSelection` 末尾再次同步。
- 菜单栏项创建但不可见：`autosaveName` / Control Center `VisibleCC` 持久化为隐藏；清除并重绑；改用 `button.image` 替代失效的自定义 `NSView` 子视图。
- 菜单栏无匹配歌词行时不更新：`update()` 增加 fallback 行索引，前奏时显示首行或最近行。
- 每次启动请求访问「下载」文件夹：选择/注册库时保存 bookmark，启动与 sync 前 `startAccessingSecurityScopedResource()`。

### Verified

- `./build.sh` 构建成功。
- 手动：菜单栏显示歌词、短句居中、长句滚至末尾停止、下拉无 `^`、浅色菜单；系统设置已允许后稳定显示。

## 2026-06-15

### Added

- 菜单栏歌词：系统状态栏显示当前歌词行（跑马灯滚动）；关闭主窗口后应用保持后台运行。
- 菜单栏歌词设置存入 SQLite `app_settings` 表：开关、最大宽度、是否显示图标。
- 数据库 schema 合并为 v1 基线（本地开发）；移除 v2–v4 分步迁移与 `display_settings` 表。
- 「视图」菜单与菜单栏项内可配置菜单栏歌词；点击菜单栏项可显示主窗口、播放/暂停、切歌。
- 主窗口顶部改用 `NSToolbar`：选择文件夹、刷新、库路径、搜索、歌词工具（弹出面板）合并为一行工具栏。

### Fixed

- 顺序播放自动切歌后，空格/菜单栏播放暂停作用于当前正在播放的曲目；仅当用户主动点选其他歌曲时才切换播放。
- 菜单栏歌词：连续两行相同文字时第二行不再卡在已滚完状态，换行后重新跑马灯。
- 菜单栏歌词使用 NSStatusItem 显示（参与系统布局，不覆盖系统图标）；宽度统一使用 `app_settings` 全局设置。
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
- 总播放列表（Schema v2）：多次选择文件夹时曲目累积到系统「全部」列表；以文件内容 SHA256（`content_hash`）去重，同内容不同路径只显示一条。
- 新增 `playlists` / `playlist_tracks` / `library_tracks` / `player_state` 表；播放进度改存 `player_state`（全局，不再绑定单个库）。
- 新增 `TrackContentHasher`、`PlaylistRepository`、`PlayerStateRepository`；`test.sh` 含数据库层自动化测试。

### Changed

- 选择文件夹改为 `registerLibrary`：已注册库保留，列表展示总播放列表而非仅当前库。
- 刷新（⌘R）同步所有已注册文件夹后重载总列表。
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
- 歌曲列表交互：保持双击播放；单击选中；空格/播放按钮在选中行与正在播放行不同时切歌，相同时暂停/继续。
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
- 修复搜索后播放再清空搜索时，总列表中丢失当前歌曲标识的问题：以 `playingTrackURL` 定位曲目，清空搜索（含搜索框 ×）后滚动到可见行。
- 正在播放曲目改用独立列表样式（`playingTrackURL`），不依赖 `NSTableView` 选中态；点击歌词区后播放标识仍保留。
- 修复单击列表无选中反馈：`NSTableCellView` 避免文字抢点击；移除每次点击触发的整表 `reloadData`；用 `selectedTrackURL` 辅助空格切歌。

### Verified

- `./build.sh` 构建成功。
- `Info.plist` 校验通过。
- 生成的 App 可执行文件为 `arm64`。
