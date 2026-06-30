# Handoff Guide

本文件用于在不同 AI 工具或开发者之间交接 Local LRC Player 的开发流程。

它只记录「怎么协作、文档怎么分工、改完怎么验证」这些不会过期的流程信息。
项目当前是什么样、有哪些功能、最近改了什么,不在这里复述 —— 那些会过期。
要了解项目状态,直接看真相来源:

- 架构与构建约定:`CLAUDE.md`
- 当前功能与使用方式:`README.md`
- 已完成的变更历史:`CHANGELOG.md`
- 待办与已知 bug:`ROADMAP.md`
- 数据库 schema:`doc/database.md`;主窗口 UI 约定:`doc/ui.md`
- 代码本身:`Sources/LocalLrcPlayer/`

项目路径:`/Users/sakuzeng/improve/coding/mac_app/local-lrc-player`

## 文档分工(Documentation Rules)

每类信息只写在一个地方,避免同一份信息散落多处需要反复同步:

- 当前真实功能和使用方式 → `README.md`
- 已完成的修改 → `CHANGELOG.md`(按日期写摘要级,不逐条复述 diff;细节 git 里有)
- 之后要做的功能、已知但未修的 bug → `ROADMAP.md`
- 架构、构建/测试方式、关键不变量 → `CLAUDE.md`
- SQLite 表结构、读写流程 → `doc/database.md`;主窗口 UI 与工具栏约定 → `doc/ui.md`
- 跨工具协作流程、交接模板 → 本文件
- 修复 bug 后,把对应条目从 `ROADMAP.md` 的 Known Bugs 移到 `CHANGELOG.md` 的 Fixed

markdown 文档一律不使用加粗(`**`)。

## 开场提示词(给新工具)

新开会话时,Claude Code 会自动加载 `CLAUDE.md`,通常无需额外开场白。
若使用不读 `CLAUDE.md` 的其它工具,可粘贴下面这段:

```text
请先读 CLAUDE.md、README.md、ROADMAP.md,以及 doc/database.md 和 doc/ui.md,
再看 Sources/LocalLrcPlayer 下的代码。

这是一个原生 macOS 本地 LRC 播放器(Swift + AppKit + AVFoundation),
不使用 Electron / Node / Rust / Xcode 工程 / Swift Package。
构建运行 ./build.sh,通过 swiftc 生成 build/LocalLrcPlayer.app。

开发要求:
1. 保持现有技术栈和构建方式不变。
2. 不要删除或覆盖已有本地音乐、歌词、Cookie、缓存文件。
3. 改完后按「文档分工」更新对应文档。
4. 改完后运行验证(见下方 Verification Checklist)。
5. 完成后按 Handoff Template 输出交接记录。
```

## 交接模板(Handoff Template)

开发完成后输出:

```text
## Handoff

本次目标:
...

修改文件:
- ...

实现内容:
- ...

验证:
- ./build.sh:通过/失败(失败原因)
- plutil:通过/失败(失败原因)
- 手动测试:...

文档更新:
- README.md / CHANGELOG.md / ROADMAP.md:...

未完成/风险:
- ...
```

## 验证清单(Verification Checklist)

每次代码修改后至少执行:

```bash
cd /Users/sakuzeng/improve/coding/mac_app/local-lrc-player
./build.sh
plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist
```

如果改了播放、歌词显示、下载歌词或文件扫描逻辑,还要做对应手动测试,
并在交接记录中写清测试结果。改了 SQLite 仓储逻辑时跑 `./test.sh`。
