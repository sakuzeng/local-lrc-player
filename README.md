# Local LRC Player

一个轻量原生 macOS 本地音乐播放器，用于播放本地音乐并显示同名 `.lrc` 同步歌词。

## 功能

- 选择本地音乐文件夹；**多次选择不同文件夹时，曲目累积到总播放列表**（同文件内容只保留一条）。
- 扫描并显示本地音乐列表。
- 播放、暂停、上一首、下一首。
- 拖动进度条跳转播放位置。
- 读取同目录同名 `.lrc` 歌词。
- 按播放进度高亮当前歌词。
- 歌词平滑滚动。
- 多语种歌词播放时原文和译文同时显示，顺序固定为原文在上、中文译文在下；高亮默认落在中文译文行。
- 记住上次选择的音乐目录。
- FLAC 播放时自动使用同名 `.m4a` 或生成 ALAC 缓存，以保证手动跳转更准确。
- 支持通过网易云或 QQ 音乐搜索并下载缺失的同名 `.lrc` 歌词。
- 下载当前歌词时支持候选结果预览和手动选择。
- 日语等多语种歌曲会尽量按同一时间戳交错输出原文和译文；网易云如果返回英文译文，也会继续追加英文译文。
- 网易云和 QQ 音乐 Cookie 分别保存到本机私有配置文件。
- 本地 SQLite 数据库索引音乐库与曲目（ID3 元数据、是否有歌词）。
- 歌曲列表搜索（歌名、歌手、专辑）。
- 刷新（⌘R）增量同步**所有已注册文件夹**并更新总播放列表。
- 记住上次音乐库、曲目与播放进度；再次打开时恢复选中状态和进度位置，不自动播放。
- 标准 macOS 菜单栏与常用快捷键（⌘Q 退出、空格播放/暂停等）。
- 搜索框支持过滤歌曲；启动时不自动聚焦，点击其他区域失焦。
- 歌曲列表中**正在播放**的曲目以加粗、主题色与浅蓝行背景标识；清空搜索或点击其他区域后仍保持，并自动滚到可见位置。

## 构建

需要本机可用 Swift 编译工具链，并链接系统 SQLite3。FLAC 自动转 ALAC 缓存依赖 Homebrew 安装的 `ffmpeg`：

```bash
brew install ffmpeg
```

```bash
cd /Users/sakuzeng/improve/coding/mac_app/local-lrc-player
./test.sh    # 运行数据库测试并构建 App
./build.sh   # 仅构建
```

构建产物：

```text
/Users/sakuzeng/improve/coding/mac_app/local-lrc-player/build/LocalLrcPlayer.app
```

也可以直接打开：

```bash
open /Users/sakuzeng/improve/coding/mac_app/local-lrc-player/build/LocalLrcPlayer.app
```

## 使用

1. 打开 `build/LocalLrcPlayer.app`。
2. 点击 `选择文件夹`。
3. 选择包含音乐文件的目录，例如：

   ```text
   /Users/sakuzeng/Downloads/tgdownloads/music
   ```

4. 可继续选择其他文件夹，歌曲会追加到同一总列表（内容相同的副本自动去重）。
5. 双击左侧歌曲开始播放；或选中后按**空格** / 点「播放」。
6. 可用搜索框过滤歌曲（点击列表或歌词区可让搜索框失焦）；新增音乐或歌词后点「刷新」即可同步全部已注册文件夹。

常用快捷键：

| 快捷键 | 功能 |
|---|---|
| ⌘Q | 退出 |
| ⌘W | 关闭窗口 |
| ⌘O | 选择文件夹 |
| ⌘R | 刷新全部已注册文件夹 |
| ⌘M | 最小化 |
| 空格 | 播放/暂停 |
| ⌘[ / ⌘] | 上一首 / 下一首 |
| ⌘⇧? | 帮助 |

## 本地数据

App 数据保存在 `~/Library/Application Support/LocalLrcPlayer/`：

| 文件 | 用途 |
|---|---|
| `LocalLrcPlayer.sqlite` | 音乐库、总播放列表、曲目索引（含内容哈希去重）、播放历史、歌词下载审计 |
| `netease-cookie.txt` | 网易云 Cookie |
| `qqmusic-cookie.txt` | QQ 音乐 Cookie |

歌词和音频仍以你选择的音乐文件夹内文件为准（同名 `.lrc`）；数据库只是索引与历史，不是第二份歌词。

数据库表结构、主键/外键与读写流程见 [doc/database.md](./doc/database.md)。

## 下载歌词

当前支持两个歌词源：

- 网易云：需要先设置 Cookie。
- QQ 音乐：需要先设置 Cookie。

使用步骤：

1. 在歌词工具栏左侧选择 `Cookie 来源`：`网易云` 或 `QQ音乐`（仅用于设置/重置对应 Cookie，不影响下载或补全时的搜索范围）。
2. 点击 `设置 Cookie`，粘贴当前歌词来源对应网站登录后的 Cookie。
3. 选择一首没有歌词的歌曲。
4. 点击 `下载当前歌词`，App 会同时搜索已设置 Cookie 的网易云和 QQ 音乐，并在同一个候选窗口按来源展示结果。
5. 点击候选结果预览歌词，确认后点击 `保存所选歌词`。

也可以点击 `补全缺失歌词`，App 会串行处理当前目录里所有没有同名 `.lrc` 的歌曲。

下载规则：

- `下载当前歌词` 会同时搜索已设置 Cookie 的网易云和 QQ 音乐，在同一个候选窗口按来源分组展示；只设置了一个来源 Cookie 时只搜索该来源。
- `下载当前歌词` 支持预览和手动选择；保存时会覆盖当前歌曲已有的同名 `.lrc`。
- `补全缺失歌词` 会同时搜索已设置 Cookie 的网易云和 QQ 音乐，按匹配分从高到低依次尝试，直到成功获取歌词并保存（单首最多尝试 8 个高分候选）。同分时先尝试网易云候选，拉取失败则自动试下一个；两个来源都有 100 分但一个无歌词时，会跳过无歌词的、保存第一个成功返回的。
- 只写入缺失的同名 `.lrc`（仅适用于补全缺失歌词）。
- 不覆盖已有 `.lrc`。
- 保存时会自动去掉行首的歌手名或角色前缀（如 `田翌臣: `、`合: `），只保留歌词正文。
- 匹配分数过低时不保存，避免写入明显错误的歌词。
- 匹配分基于规范化后的歌名与 API 返回的歌手计算：歌名会从混杂字段中提取后再比对；歌手仅认 API `artists`，且与本地歌手完全一致才加分。
- 下载成功后会刷新当前目录，左侧“无歌词”标记会更新。

Cookie 保存位置：

```text
~/Library/Application Support/LocalLrcPlayer/netease-cookie.txt
~/Library/Application Support/LocalLrcPlayer/qqmusic-cookie.txt
```

文件权限会设置为仅当前用户可读写。

多语种输出规则：

- 优先输出原文。
- 如果歌词来源返回翻译歌词，则在同一时间戳后追加译文。
- 如果网易云返回英文译文，则继续追加英文译文。
- 播放显示时，原文和中文译文会同时显示，顺序固定为原文在上、中文译文在下；日文歌为日文在上，英文歌为英文在上；高亮默认落在中文译文行。
- 格式示例：

  ```text
  [00:00.230]君と夏の終わり　将来の夢
  [00:00.230]与你在夏末约定　将来的梦想
  [00:00.230]Ten years later in August
  ```

## 歌词规则

歌词文件必须和音乐文件在同一个目录，并且主文件名相同：

```text
要不要买菜 - 下山.flac
要不要买菜 - 下山.lrc
```

支持标准 LRC 时间轴格式：

```text
[00:15.04]要想练就绝世武功
[00:16.98]就要忍受常人难忍受的痛
```

一行多个时间戳也支持：

```text
[00:15.04][01:20.10]重复的一句歌词
```

## 支持格式

- `.mp3`
- `.m4a`
- `.flac`
- `.wav`
- `.aac`
- `.aiff`
- `.aif`

## 项目结构

```text
Sources/LocalLrcPlayer/
  AppDatabase.swift             SQLite 连接与 schema 迁移
  LibraryRepository.swift       音乐库 CRUD、播放状态
  TrackRepository.swift         曲目增量 sync 与查询
  PlayHistoryRepository.swift   播放历史
  LyricLogRepository.swift      歌词下载审计
  TrackMetadataReader.swift     AVAsset 读取 ID3 元数据
  DatabaseModels.swift          数据库记录模型
  AppDelegate.swift             应用生命周期、About/Help
  AppMenuBuilder.swift          标准 macOS 菜单栏
  main.swift                    App 启动入口
  PlayerWindowController.swift  主窗口：绑定、Cookie、快捷键、焦点
  PlayerWindowController+Library.swift      音乐库加载与刷新
  PlayerWindowController+Playback.swift     播放、进度、歌词显示
  PlayerWindowController+LyricsDownload.swift  歌词下载与补全
  Result+Success.swift          Result 便捷扩展
  PlayerWindowLayout.swift      主窗口 UI 布局
  TrackListDataSource.swift     左侧歌曲列表
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
  LyricFileWriter.swift         同名 .lrc 写入
```

## 开发

本项目不使用 Xcode 工程、Swift Package 或第三方依赖，直接通过 `swiftc` 编译，并链接系统 `SQLite3`。新增 Swift 文件后不需要手动改编译列表，`build.sh` 会自动收集：

```text
Sources/LocalLrcPlayer/**/*.swift
```

每次修改后运行：

```bash
./build.sh
```

## 常见问题

### 再次打开 App 就自动播放

当前版本启动时只恢复上次选中的歌曲和进度条位置，不会自动播放。需要手动点「播放」或按空格才会开始。

### 搜索框一直亮着 / 无法失焦

启动时默认焦点在歌曲列表，不在搜索框。点击列表、歌词区或工具栏按钮后，搜索框会失焦；只有点击搜索框本身才会进入输入状态。

### 搜索后播放，取消搜索找不到当前歌

搜索过滤后播放某首，再点搜索框 **×** 或删光关键字，总列表会按正在播放的文件路径重新定位该行（加粗 + 浅蓝背景），并滚动到可见区域。该标识不依赖表格选中态，点击歌词区等处不会消失。

### 有歌但没有歌词

确认是否存在同名 `.lrc` 文件，例如：

```text
银临 - 棠梨煎雪.flac
银临 - 棠梨煎雪.lrc
```

### 拖动进度条后歌词不同步

当前版本已经将拖动分成“预览歌词”和“松手后提交 seek”。对于 `.flac`，App 会优先使用同名 `.m4a`，没有时会用 `ffmpeg` 生成 ALAC 缓存再播放，因为 AVPlayer 直接播放 FLAC 时手动 seek 可能落点不准。

当前代码查找的 `ffmpeg` 路径是：

```text
/opt/homebrew/bin/ffmpeg
```

缓存位置在 macOS 用户缓存目录下：

```text
~/Library/Caches/LocalLrcPlayer/Transcoded
```

### 修改后打开还是旧效果

先退出当前 App，再重新构建并打开：

```bash
./build.sh
open build/LocalLrcPlayer.app
```

### 下载歌词时仍弹出钥匙串密码

新版已经不再使用 Keychain 保存 Cookie。请先退出旧 App，重新打开新版。如果仍弹出钥匙串密码，说明当前运行的还是旧版本。

## 当前限制

- 不读取音频内嵌歌词。
- 不做封面、播放模式、全局快捷键。
- FLAC 第一次播放可能需要等待生成 ALAC 缓存。
- 目前只支持网易云和 QQ 音乐，不支持酷狗/酷我等其他源。
- 网易云接口可用性取决于 Cookie 是否有效，以及网易云侧接口策略。
- QQ 音乐接口使用本机保存的 QQ 音乐 Cookie，请确认 Cookie 仍有效。
- 英文译文只有在网易云接口返回对应字段时才会写入；没有英文译文时只输出原文和已有译文。

## 开发记录

- 已完成的变更记录在 `CHANGELOG.md`。
- 后续计划和想法记录在 `ROADMAP.md`。
- 跨 AI 工具或开发者的开场提示词和交接模板记录在 `HANDOFF.md`。
