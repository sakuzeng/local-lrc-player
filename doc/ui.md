# 主窗口 UI 说明

本文件记录主窗口布局约定与 AppKit 工具栏实践经验，便于后续加按钮、换位置时不重复踩坑。

相关代码：`PlayerWindowLayout.swift`、`PlayerWindowToolbar.swift`、`PlayerWindowController.swift`。

---

## 布局分区

```text
┌─ NSToolbar（右侧）────────────────────────────────────┐
│  [文件夹 | 刷新]  ←flexibleSpace→  [搜索框]          │
├──────────────────────────────────────────────────────┤
│  曲目列表          │  歌词区                          │
│  ┌ listHeaderBar ─┐│                                  │
│  │ 歌曲·N    [定位]││  LyricsView                      │
│  TrackTableView    │                                  │
│  [◀ ▶ ▶] [模式]    │  [━━━━ 进度条 ━━━━] 00:00/03:45  │
├──────────────────────────────────────────────────────┤
│  statusLabel（全宽）                                    │
└──────────────────────────────────────────────────────┘
```

| 区域 | 职责 |
|---|---|
| **工具栏** | 音乐库操作（选文件夹、刷新）+ 全局搜索 |
| **列表顶栏** `listHeaderBar` | 当前列表标题（日后可换播放列表名）+ **列表导航**按钮 |
| **列表导航** `listNavigationStack` | 与列表强相关的操作（定位正在播放等），便于横向扩展 |
| **列表底栏** `transportBar` | 传输控制 pill + 播放模式（在 split 左列内） |
| **歌词底栏** `progressBar` | 进度条 + 时间，左右 28pt 与歌词 `textContainerInset` 对齐（在 split 右列内） |

播放底栏放在各自 split 子视图内，**不要**在 split 外再用 `widthAnchor` 绑定列宽，否则易触发 Auto Layout 冲突导致启动崩溃。

窗口样式：`fullSizeContentView` + `toolbarStyle = .unified` + 全窗 `NSVisualEffectView` 毛玻璃。

---

## NSToolbar：两个框之间的间隔是怎么来的

当前工具栏项顺序（`PlayerWindowToolbar.toolbarDefaultItemIdentifiers`）：

```text
.playerChooseFolder → .playerRefresh → .flexibleSpace → .playerSearch
```

### 1. 两个独立「框」

| 控件 | 实现 | 视觉效果 |
|---|---|---|
| 文件夹 + 刷新 | 两个带 `item.image` 的 `NSToolbarItem` | macOS 11+ **unified 工具栏**会把**相邻图标项自动合并**成一个圆角 pill |
| 搜索框 | `item.view` 内嵌 `NSSearchField`（自定义视图） | 自定义 `view` **不会**与前面的图标 pill 合并，搜索框自带圆角样式，形成第二个框 |

### 2. 中间间隔

- **`.flexibleSpace`**：系统弹性空白，占据「刷新」与「搜索」之间的剩余水平空间；窗口越宽，中间拉得越开。
- 图标项（`image`）与搜索项（`view`）类型不同，系统也不会画进同一条 pill，视觉上天然分离。

### 3. 在工具栏再加独立按钮时的坑（已验证）

若把「定位正在播放」等按钮做成**相邻的 `item.image` 工具栏项**：

- 会与文件夹/刷新**合成一条长 pill**，难以拆成用户期望的多段分割；
- 中间插自定义「空白 gap」`NSToolbarItem`（固定宽度 `NSView`）**仍可能被系统视觉上连成一体**；
- 为每个逻辑组单独做 `item.view` 圆角容器（`ToolbarIconPillView`）可以强制分组，但样式难与系统原生 pill 完全一致。

**结论（当前约定）**：

- **工具栏**：只放「音乐库 + 搜索」这类全局操作；保持 `[图标|图标] + flexibleSpace + [搜索 view]` 模式。
- **列表相关导航**（定位、日后播放列表切换等）：放在 **`listNavigationStack`**（列表顶栏右侧），不放进工具栏。

---

## 列表顶栏 `listHeaderBar`

实现：`PlayerWindowLayout.configureListContainer()`。

- **左侧** `listTitleLabel`：默认 `歌曲 · {曲目数}`；无曲目时隐藏顶栏。日后可替换为当前播放列表名称。
- **右侧** `listNavigationStack`：水平 `NSStackView`，当前含 `locatePlayingButton`（`scope`）。
- 空状态（无库 / 无曲 / 搜索无结果）时 `listHeaderBar.isHidden = true`。

### 定位正在播放

- 入口：列表顶栏 `scope` 按钮 → `PlayerWindowController.locatePlayingTrack()`。
- 行为：滚动并选中正在播放行；若搜索过滤掉了当前曲，先清空搜索再定位。
- 启用条件：`playingTrackURL != nil`（`updateControlState`）。

扩展方式：在 `listNavigationStack` 中 `addArrangedSubview` 新按钮即可，无需改工具栏。

---

## 播放模式（播放区）

- 按钮：`playbackModeButton`，位于列表列底栏 `transportBar`，与传输控制 pill 间距 20pt，单独 `quaternarySystemFill` pill。
- 图标：`arrow.right.to.line.compact` / `repeat.1` / `shuffle`；单曲循环与随机为分层主题色，顺序模式为次要色。
- 持久化：`player_state.playback_mode`（schema v3）。
- **顺序播放**：列表播完后**从第一首继续**（非停止）；单曲循环重播当前曲；随机维护 `shuffleHistory` 支持上一首回退。

## 总列表排序

- 查询按 `playlist_tracks.sort_order`；每次 `TrackRepository.sync` 结束调用 `reorderMasterPlaylist` 重算。
- 规则：先 `library_id` 升序（库注册顺序），同库内按列表显示名 `localizedStandardCompare`（有 ID3 用「歌手 - 歌名」，否则文件名不含扩展名）。
- 用户感觉顺序不对时，先 **⌘R 刷新** 触发重排。

---

## 维护约定

- 改工具栏项顺序或新增工具栏控件时，先对照本文 **NSToolbar** 一节，避免破坏两段 pill 布局。
- 改列表顶栏或播放区控件时，同步更新本文与 `HANDOFF.md`。
- 用户可见行为变更写入 `CHANGELOG.md`。
