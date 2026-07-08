# 主窗口 UI 说明

本文件记录主窗口布局约定与 AppKit 工具栏实践经验，便于后续加按钮、换位置时不重复踩坑。

相关代码：`PlayerWindowLayout.swift`、`PlayerWindowToolbar.swift`、`PlayerWindowController.swift`。

---

## 布局分区

```text
┌─ NSToolbar（右侧）────────────────────────────────────┐
│  [文件夹 | 刷新]  ←flexibleSpace→  [搜索框]          │
├──────────────────────────────────────────────────────┤
│  曲目列表          │  [封面|歌名/歌手] ← nowPlayingBar │
│  ┌ listHeaderBar ─┐│                                  │
│  │ 歌曲·N    [定位]││  LyricsView                      │
│  TrackTableView    │                                  │
│  [◀ ▶ ▶] [模式]    │  [━━━ 进度条 ━━━] 00:00/03:45 [🔊]│
├──────────────────────────────────────────────────────┤
│  statusLabel（全宽）                                    │
└──────────────────────────────────────────────────────┘
```

| 区域 | 职责 |
|---|---|
| 工具栏 | 音乐库操作（选文件夹、刷新）+ 全局搜索 |
| 列表顶栏 `listHeaderBar` | 当前列表标题（日后可换播放列表名）+ 列表导航按钮 |
| 列表导航 `listNavigationStack` | 与列表强相关的操作（定位正在播放等），便于横向扩展 |
| 列表底栏 `transportBar` | 传输控制 pill + 播放模式（在 split 左列内） |
| 歌词顶栏 `nowPlayingBar` | 正在播放信息块（36pt 圆角封面 + 歌名/歌手，可截断，无曲目时隐藏），水平居中呼应歌词居中排版、两侧至少 28pt（在 split 右列内）。封面：内嵌图 → `ArtworkCache`/下载兜底 → 占位音符 |
| 歌词底栏 `progressBar` | 进度条 + 时间 + 音量喇叭按钮（点击弹 transient popover 竖向滑杆），左右 28pt 与歌词 `textContainerInset` 对齐（在 split 右列内） |

播放底栏放在各自 split 子视图内，不要在 split 外再用 `widthAnchor` 绑定列宽，否则易触发 Auto Layout 冲突导致启动崩溃。

窗口样式：`fullSizeContentView` + `toolbarStyle = .unified` + 全窗 `NSVisualEffectView` 毛玻璃；
毛玻璃与内容之间夹一层 `AmbientBackgroundView`（封面主色氛围色斑，由 `updateNowPlaying` 的封面参数驱动）。
歌词顶栏 `nowPlayingBar` 无曲目时高度收 0（`nowPlayingBarHeightConstraint`），信息块用 centerY 居中而非上下 pin，避免高度为 0 时约束冲突。

---

## NSToolbar：两个框之间的间隔是怎么来的

当前工具栏项顺序（`PlayerWindowToolbar.toolbarDefaultItemIdentifiers`）：

```text
.playerChooseFolder → .playerRefresh → .flexibleSpace → .playerSearch
```

### 1. 两个独立「框」

| 控件 | 实现 | 视觉效果 |
|---|---|---|
| 文件夹 + 刷新 | 两个带 `item.image` 的 `NSToolbarItem` | macOS 11+ unified 工具栏会把相邻图标项自动合并成一个圆角 pill |
| 搜索框 | `item.view` 内嵌 `NSSearchField`（自定义视图） | 自定义 `view` 不会与前面的图标 pill 合并，搜索框自带圆角样式，形成第二个框 |

### 2. 中间间隔

- `.flexibleSpace`：系统弹性空白，占据「刷新」与「搜索」之间的剩余水平空间；窗口越宽，中间拉得越开。
- 图标项（`image`）与搜索项（`view`）类型不同，系统也不会画进同一条 pill，视觉上天然分离。

### 3. 在工具栏再加独立按钮时的坑（已验证）

若把「定位正在播放」等按钮做成相邻的 `item.image` 工具栏项：

- 会与文件夹/刷新合成一条长 pill，难以拆成用户期望的多段分割；
- 中间插自定义「空白 gap」`NSToolbarItem`（固定宽度 `NSView`）仍可能被系统视觉上连成一体；
- 为每个逻辑组单独做 `item.view` 圆角容器（`ToolbarIconPillView`）可以强制分组，但样式难与系统原生 pill 完全一致。

结论（当前约定）：

- 工具栏：只放「音乐库 + 搜索」这类全局操作；保持 `[图标|图标] + flexibleSpace + [搜索 view]` 模式。
- 列表相关导航（定位、日后播放列表切换等）：放在 `listNavigationStack`（列表顶栏右侧），不放进工具栏。

---

## 列表顶栏 `listHeaderBar`

实现：`PlayerWindowLayout.configureListContainer()`。

- 左侧 `listTitleLabel`：默认 `歌曲 · {曲目数}`；无曲目时隐藏顶栏。日后可替换为当前播放列表名称。
- 右侧 `listNavigationStack`：水平 `NSStackView`，当前含 `locatePlayingButton`（`scope`）。
- 空状态（无库 / 无曲 / 搜索无结果）时 `listHeaderBar.isHidden = true`。

### 定位正在播放

- 入口：列表顶栏 `scope` 按钮 → `PlayerWindowController.locatePlayingTrack()`。
- 行为：滚动并选中正在播放行；若搜索过滤掉了当前曲，先清空搜索再定位。
- 启用条件：`playingTrackURL != nil`（`updateControlState`）。

扩展方式：在 `listNavigationStack` 中 `addArrangedSubview` 新按钮即可，无需改工具栏。

---

## 播放模式（播放区）

- 按钮：`playbackModeButton`，位于列表列底栏 `transportBar`，与传输控制 pill 间距 20pt，单独 `quaternarySystemFill` pill。
- 图标：`arrow.right.to.line.compact` / `repeat.1` / `shuffle`；当前模式统一用分层主题色高亮。
- 持久化：`player_state.playback_mode`（schema v3）。
- 顺序播放：列表播完后从第一首继续（非停止）；单曲循环重播当前曲；随机维护 `shuffleHistory` 支持上一首回退。

## 总列表排序

- 查询按 `playlist_tracks.sort_order`；每次 `TrackRepository.sync` 结束调用 `reorderMasterPlaylist` 重算。
- 规则：先 `library_id` 升序（库注册顺序），同库内按列表显示名 `localizedStandardCompare`（有 ID3 用「歌手 - 歌名」，否则文件名不含扩展名）。
- 用户感觉顺序不对时，先 ⌘R 刷新 触发重排。

---

## 菜单栏歌词（`MenuBarLyricsController`）

相关代码：`MenuBarLyricsController.swift`、`MenuBarLyricsStatusImage.swift`、`MenuBarStatusItemVisibility.swift`、`AppSettingsRepository`（`menu_bar_lyrics_max_width` 等为最大宽度）。

| 行为 | 说明 |
|---|---|
| 显示 | macOS 26 使用 `NSStatusItem` + `button.image` 位图（白字）；短句在 pill 内居中；宽度随内容收缩，不超过设置上限 |
| 长句 | 播放中自左向右滚动，滚到行尾停下；换行后重新从行首开始；暂停时显示截断静态文本 |
| 菜单 | `statusItem.menu` 原生弹出（避免 `popUp` 顶部 `^`）；`NSAppearance.aqua` 浅色菜单 |
| 设置 | 开关 / 最大宽度（120·140·160 或 80–400 自定义）/ 音符图标 → `app_settings` |
| 权限 | 不修改系统设置；若不可见，`MenuBarVisibilityGuide` 提示用户在「系统设置 → 菜单栏」打开本应用 |

音乐库若在「下载」等受保护目录，见 `LibraryBookmarkStore`（选择文件夹时写入 Security-Scoped Bookmark）。

---

## 维护约定

- 改工具栏项顺序或新增工具栏控件时，先对照本文 NSToolbar 一节，避免破坏两段 pill 布局。
- 改列表顶栏或播放区控件时，同步更新本文与 `HANDOFF.md`。
- 用户可见行为变更写入 `CHANGELOG.md`。
