# SQLite 数据库说明

## 概览

Local LRC Player 使用本机 SQLite 作为索引与状态层，不替代磁盘上的音频与 `.lrc` 文件。

| 项目 | 值 |
|---|---|
| 引擎 | SQLite 3（系统 `-lsqlite3`） |
| 文件路径 | `~/Library/Application Support/LocalLrcPlayer/LocalLrcPlayer.sqlite` |
| Schema 版本 | `PRAGMA user_version = 6`（v1 基线 + v2 窗口列 + v3 播放模式 + v4 音量 + v5 播放里程碑 + v6 往年今日） |
| 外键 | 开启（`PRAGMA foreign_keys = ON`） |
| 并发 | 单连接 + `DispatchQueue` 串行读写 |

### 设计原则

1. 文件为准：`.lrc` 与音频仍在用户所选音乐文件夹内；`tracks.has_lyric` 只是缓存标记。
2. Cookie 不进库：网易云 / QQ 音乐 Cookie 仍在 `netease-cookie.txt`、`qqmusic-cookie.txt`。
3. 总播放列表：UI 列表读系统内置 `playlists.id = 1`（「全部」），多次选文件夹累积曲目。
4. 内容去重：`tracks.content_hash`（SHA256）为业务唯一键；同内容不同路径只一条 `tracks` 行。
5. 增量 sync：`library_tracks` 以 `mtime/size` 判断是否需要重算 hash / 读 ID3。
6. 级联删除：删除 `tracks` 时 CASCADE 清理 history / log / playlist_tracks。

---

## ER 关系图

```mermaid
erDiagram
    libraries ||--o{ library_tracks : scans
    tracks ||--o{ library_tracks : linked
    playlists ||--o{ playlist_tracks : contains
    tracks ||--o{ playlist_tracks : member
    tracks ||--o{ play_history : played
    tracks ||--o{ lyric_download_log : audited
    player_state }o--o| tracks : lastTrack

    app_settings {
        INTEGER id PK
        INTEGER menu_bar_lyrics_enabled
        REAL menu_bar_lyrics_max_width
        INTEGER menu_bar_lyrics_show_icon
    }

    libraries {
        INTEGER id PK
        TEXT path UK
        TEXT display_name
        INTEGER last_track_id
        REAL last_position
        REAL last_scanned_at
        INTEGER is_active
    }

    tracks {
        INTEGER id PK
        INTEGER library_id FK
        TEXT file_path UK
        TEXT content_hash UK
        TEXT file_name
        REAL file_mtime
        INTEGER file_size
        TEXT title
        TEXT artist
        TEXT album
        REAL duration
        INTEGER has_lyric
        REAL updated_at
    }

    library_tracks {
        INTEGER library_id PK_FK
        TEXT file_path PK
        INTEGER track_id FK
        REAL file_mtime
        INTEGER file_size
    }

    playlists {
        INTEGER id PK
        TEXT name
        INTEGER is_system
    }

    playlist_tracks {
        INTEGER playlist_id PK_FK
        INTEGER track_id PK_FK
        REAL added_at
        INTEGER sort_order
    }

    player_state {
        INTEGER id PK
        INTEGER last_track_id
        REAL last_position
        REAL window_origin_x
        REAL window_origin_y
        REAL window_width
        REAL window_height
        TEXT playback_mode
        REAL volume
    }
```

---

## 表结构

### `libraries` — 已注册音乐文件夹

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 库 ID |
| `path` | TEXT | NOT NULL, UNIQUE | 标准化绝对路径 |
| `display_name` | TEXT | | 文件夹名 |
| `last_track_id` | INTEGER | | 遗留列，播放恢复用 `player_state` |
| `last_position` | REAL | NOT NULL, DEFAULT 0 | 遗留列 |
| `last_scanned_at` | REAL | | 上次 sync 完成时间 |
| `is_active` | INTEGER | NOT NULL, DEFAULT 0 | 1 = 最近一次选择的文件夹（仅 UI 展示） |

---

### `tracks` — 全局曲目索引（按内容去重）

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 内部 ID（`AUTOINCREMENT` 不重用已删 ID） |
| `library_id` | INTEGER | NOT NULL, FK → `libraries(id)` | 首次发现该 hash 的库 |
| `file_path` | TEXT | NOT NULL, UNIQUE | 当前用于播放的 canonical 路径 |
| `content_hash` | TEXT | UNIQUE | 文件内容 SHA256（十六进制） |
| `file_name` … `updated_at` | | | 同 v1 |

去重规则：sync 时若 `content_hash` 已存在，不 INSERT 新行，只更新 `library_tracks` 并确保在总播放列表中。

---

### `library_tracks` — 某库扫描到的路径

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `library_id` | INTEGER | PK, FK → `libraries(id)` CASCADE | 库 |
| `file_path` | TEXT | PK | 该库下的绝对路径 |
| `track_id` | INTEGER | NOT NULL, FK → `tracks(id)` CASCADE | 对应全局 track |
| `file_mtime` | REAL | NOT NULL | 缓存 mtime |
| `file_size` | INTEGER | NOT NULL | 缓存 size |

唯一：`(library_id, track_id)`

同 hash 多路径时，每个库各一行 `library_tracks`，共用一条 `tracks`。

---

### `playlists` / `playlist_tracks` — 播放列表

`playlists`

| 列 | 说明 |
|---|---|
| `id = 1`, `name = '全部'`, `is_system = 1` | 系统总列表（当前 UI 唯一使用） |

`playlist_tracks`

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `playlist_id` | INTEGER | PK, FK → `playlists(id)` CASCADE | 列表 |
| `track_id` | INTEGER | PK, FK → `tracks(id)` CASCADE | 曲目 |
| `added_at` | REAL | NOT NULL | 加入时间 |
| `sort_order` | INTEGER | NOT NULL | 列表排序 |

索引：`idx_playlist_tracks_order (playlist_id, sort_order)`

---

### `player_state` — 全局播放进度与主窗口

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER | 固定为 `1`（CHECK 约束） |
| `last_track_id` | INTEGER | 上次选中/播放的 `tracks.id` |
| `last_position` | REAL | 上次进度（秒） |
| `window_origin_x` | REAL | 主窗口 frame 原点 x（v2；NULL = 未保存，启动时居中） |
| `window_origin_y` | REAL | 主窗口 frame 原点 y |
| `window_width` | REAL | 主窗口宽度 |
| `window_height` | REAL | 主窗口高度 |
| `playback_mode` | TEXT | 播放模式（v3；`sequential` / `repeatOne` / `shuffle`，默认 `sequential`） |
| `volume` | REAL | 音量 0–1（v4；默认 1，读写时钳制到区间内） |

---

### `app_settings` — 全局 UI 偏好

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER | 固定为 `1`（CHECK 约束） |
| `menu_bar_lyrics_enabled` | INTEGER | 是否在菜单栏显示歌词（0/1，默认 1） |
| `menu_bar_lyrics_max_width` | REAL | 菜单栏歌词最大宽度 pt（默认 160；预设 120/140/160 或自定义 80–400） |
| `menu_bar_lyrics_show_icon` | INTEGER | 是否显示音符图标（0/1，默认 1）；图标固定在歌词右侧 |
| `milestone_alerts_enabled` | INTEGER | 播放次数达到里程碑时是否弹窗（0/1，默认 1；v5） |
| `memory_alerts_enabled` | INTEGER | 启动时是否回顾「往年今日」（0/1，默认 1；v6） |
| `last_memory_shown_on` | TEXT | 「往年今日」上次弹出的日期 `YYYY-MM-DD`（本地时区，NULL 表示没弹过；v6） |

---

### `play_history` — 播放记录与里程碑计数

通过 `track_id` FK → `tracks(id)` ON DELETE CASCADE。v1 三列不变，v5 增加 `counted`。

| 列 | 类型 | 说明 |
|---|---|---|
| `counted` | INTEGER | 是否算作一次「有效播放」（0/1，默认 0；v5） |

关键约定：

- 每次开始播放都插一行（含跳过），`recordPlayback` 返回 rowid；听满阈值后由 `markCounted` 回标 `counted = 1`。
- 有效播放沿用 Last.fm 的 scrobble 规则：曲长 > 30 秒，且实际听满一半或 4 分钟（取较小者）。
  判定累加的是真实播放秒数（tick 里累加），不是 `currentTime`，否则拖动进度条就能骗过去。
- 里程碑只数 `counted = 1` 的行。v5 迁移给历史行一律留默认 0，
  所以里程碑从功能上线后重新起算 —— 否则一批老歌会在首次启动时集体弹窗。
- 「首次播放时间」`firstPlayedAt` 取全量历史的 `MIN(started_at)`，不看 `counted`：
  「这首歌你从哪天开始听」独立于计数口径，上线前的历史同样成立。

「往年今日」（`OnThisDayMemory` + `mostPlayedTrack(onDay:)`）：

- 按 `date(started_at,'unixepoch','localtime')` 分组，取那天播放次数最多的一首（同票取最早那次）。
  同样不看 `counted` —— 回顾的是「你那天在听什么」，跳过的播放也是当天的真实痕迹。
- 偏移量按 12 → 6 → 3 → 1 个月依次取第一个有记录的。现在只可能命中 1 个月；
  等历史攒够一年，同一段代码自己变成真正的「往年今日」，文案也自动从「1 个月前」变成「1 年前」。
- 往前推月份必须走 `Calendar.date(byAdding: .month,)`，不能减固定秒数：
  3 月 31 日减一个月是 2 月 28/29 日，减 30 天则会落到 3 月 1 日。
- 每天最多弹一次，靠 `app_settings.last_memory_shown_on` 去重；那天没有记录就安静，不弹空窗。

### `lyric_download_log`

与 v1 相同，通过 `track_id` FK → `tracks(id)` ON DELETE CASCADE。

---

## 代码与 Repository 映射

```text
AppDatabase.swift           打开 DB、schema v1 初始化
TrackContentHasher.swift    SHA256 流式 hash
DatabaseModels.swift        LibraryRecord / TrackRecord
LibraryRepository.swift     registerLibrary、allLibraries
TrackRepository.swift       sync（hash 去重）、masterPlaylistTracks
PlaylistRepository.swift    总列表查询、ensureInMasterPlaylist
PlayerStateRepository.swift player_state 读写（含主窗口 frame）
AppSettingsRepository.swift app_settings 读写（菜单栏歌词设置）
PlayHistoryRepository.swift play_history 记录/计数/首播时间
LyricLogRepository.swift    lyric_download_log INSERT
MenuBarLyricsController.swift 菜单栏歌词 UI + 设置菜单
```

---

## 典型读写流程

### 1. 启动 App

```text
migrate → v1
LibraryRepository.allLibraries()
TrackRepository.syncAll(libraries)
PlaylistRepository.masterPlaylistTracks()
PlayerStateRepository.playbackState() → restoreLastSelection
```

### 2. 用户选择文件夹

```text
LibraryRepository.registerLibrary(url)  // 累积注册，不清空其他库
TrackRepository.sync(libraryId, folderURL)
  → 算 content_hash
  → 已存在 hash：link library_tracks + playlist，跳过 INSERT
  → 新 hash：INSERT tracks + library_tracks + playlist_tracks
reloadMasterPlaylist()
```

### 3. 刷新（⌘R）

```text
TrackRepository.syncAll(all libraries)
reloadMasterPlaylist()
```

### 4. 删除行为

| 操作 | 结果 |
|---|---|
| 某库下文件删除 | 删对应 `library_tracks`；若同 hash 其他路径仍在 → 保留 `tracks` |
| 某 hash 所有路径消失 | DELETE `tracks` → CASCADE 清理 playlist/history/log |
| `tracks.id` 删除 | ID 不重用；`player_state.last_track_id` 无效时 UI 回退首行 |
| 设置中移除整个文件夹 | `TrackRepository.removeLibrary`：删该库全部 `library_tracks` → 按 hash 决定去留 `tracks` → 删 `libraries` 行；共有曲目重定向 `library_id` / 规范 `file_path`；若 `player_state.last_track_id` 被删则清空 |

### 5. 用户从设置移除文件夹

```text
SettingsWindowController → LibraryRepository.deleteLibrary(id)
  → TrackRepository.removeLibrary(libraryId)
  → 若 was_active：将另一库标为 is_active
  → PlayerWindowController.handleLibraryRemoved()
```

---

## 测试

```bash
./test.sh
```

覆盖：内容 hash、跨库去重、多库累积、播放状态、`library_tracks` 删除后保留副本、`app_settings` 默认值与更新、整库移除后共有曲目保留与 `player_state` 清理、音量默认值/持久化/越界钳制、里程碑开关默认值与互不覆盖、有效播放计数与首播时间口径、
往年今日的按日聚合/月份回推的短月边界/偏移量优先级。

---

## 手动 inspection

```bash
sqlite3 ~/Library/Application\ Support/LocalLrcPlayer/LocalLrcPlayer.sqlite "PRAGMA user_version;"
sqlite3 ~/Library/Application\ Support/LocalLrcPlayer/LocalLrcPlayer.sqlite ".tables"

# 总播放列表曲目数
sqlite3 ~/Library/Application\ Support/LocalLrcPlayer/LocalLrcPlayer.sqlite \
  "SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = 1;"

# 按 hash 查重复（应为 0 行）
sqlite3 ~/Library/Application\ Support/LocalLrcPlayer/LocalLrcPlayer.sqlite \
  "SELECT content_hash, COUNT(*) c FROM tracks GROUP BY content_hash HAVING c > 1;"
```

---

## 备份与迁移

备份 `~/Library/Application Support/LocalLrcPlayer/` 整个目录即可。换机后音乐与 `.lrc` 需单独拷贝；路径变化后重新选文件夹 sync。

本地开发若调整了 schema 基线，删除旧库后重启 App 即可重建：

```bash
rm ~/Library/Application\ Support/LocalLrcPlayer/LocalLrcPlayer.sqlite
```

后续结构变更：在 `AppDatabase.swift` 增加 `migrateToV2` 等步骤，并将 `currentSchemaVersion` 递增。

---

## 后续扩展（ROADMAP）

- 用户自定义 `playlists`（非 system）
- FTS5 全文搜索
- ~~库管理 UI（从总列表移除某文件夹）~~（已在设置窗口实现）
