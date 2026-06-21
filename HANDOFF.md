# Handoff Guide

本文件用于在不同 AI 工具或开发者之间交接 Local LRC Player 的开发上下文。

## Current State

更新时间：2026-06-15

项目路径：

```text
/Users/sakuzeng/improve/coding/mac_app/local-lrc-player
```

当前项目是一个原生 macOS 本地 LRC 播放器：

- 语言和框架：Swift + AppKit + AVFoundation。
- 构建方式：不使用 Xcode 工程、不使用 Swift Package，直接运行 `./build.sh`，通过 `swiftc` 生成 `.app`。
- 构建产物：`build/LocalLrcPlayer.app`。
- 目标平台：macOS。

当前已实现功能：

- 选择本地音乐文件夹，并记住上次选择的目录。
- 扫描 `.mp3`、`.m4a`、`.flac`、`.wav`、`.aac`、`.aiff`、`.aif`。
- 左侧显示歌曲列表，没有同名 `.lrc` 的歌曲标注“无歌词”。
- 双击播放，支持播放/暂停、上一首、下一首、进度条 seek。
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

最近关键修复和设计决策：

- `main.swift` 已拆分成多个职责模块，主协调逻辑在 `PlayerWindowController.swift`。
- 为避免 macOS 钥匙串反复弹密码，Cookie 存储从 Keychain 改为本机私有配置文件。
- FLAC 手动拖动进度条后歌词和音频不同步，根因是 AVPlayer 直接 seek FLAC 落点不准；当前通过 ALAC 缓存规避。
- QQ 音乐旧搜索接口 `client_search_cp` 会返回空候选，已改用 `musicu.fcg` 的 `DoSearchForQQMusicDesktop`。
- 歌词候选窗口曾经卡在“正在加载歌词预览”，已改为非模态窗口，并为网易云歌词详情请求增加超时和降级请求。
- 日语歌播放时中日文高亮来回切换，已在 `LrcParser.activeLineIndex` 中让同一时间戳组内优先高亮中文译文，日文原文仍保留显示。
- 多语种歌词显示顺序不一致，已在 `LrcParser.normalizedDisplayOrder` 中按组内语言组合固定为原文在上、中文译文在下；日文歌为日文在上，英文歌为英文在上。
- 下载保存歌词时会去掉行首歌手名/角色前缀（如 `田翌臣: `、`合: `），在 `LyricFormatter.stripSingerPrefix` 中处理。
- 下载当前歌词双源搜索已在 `LyricSearchService.searchAllCandidates` 和 `LyricCandidateDialog` 中实现，按网易云/QQ 音乐分组展示候选。
- 下载当前歌词保存时会覆盖已有同名 `.lrc`；补全缺失歌词仍只写入缺失文件。
- 补全缺失歌词时，已设置 Cookie 的网易云和 QQ 音乐会合并候选，按匹配分依次尝试直到成功返回歌词；见 `LyricSearchService.downloadBestAvailableLyric`。

当前主要源码文件：

```text
Sources/LocalLrcPlayer/
  AppDelegate.swift             应用生命周期
  main.swift                    App 启动入口
  PlayerWindowController.swift  主窗口协调逻辑
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

最近一次本地验证：

- `./build.sh`：通过。
- `plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist`：通过。
- 生成的可执行文件：`Mach-O 64-bit executable arm64`。

## Opening Prompt

将下面这段作为新工具的开场提示词：

```text
请先阅读这个项目的 README.md、CHANGELOG.md、ROADMAP.md 和 HANDOFF.md，然后再查看 Sources/LocalLrcPlayer 下的代码。

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
