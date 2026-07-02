---
name: fixbug
description: 本项目(LocalLrcPlayer, 原生 macOS AppKit 音乐播放器)的改 bug + 记录流程, 强调 复现→定位根因→最小修复→加回归测试→真机验证→登记记录 的闭环, 修完必须把 bug 记进 CHANGELOG 并从 ROADMAP 已知 bug 里勾掉。只要用户在本项目里描述某个缺陷并想修, 就应使用本 skill —— 即使没明说"改 bug", 例如"歌词不同步/对不上""重启后高亮丢了""切歌偶尔崩溃""FLAC 拖动进度不准""菜单栏歌词不显示""随机播放会重复同一首"。做新功能/增强请改用 feature skill。
---

# fixbug —— LocalLrcPlayer 改 bug + 记录流程

修 bug 和做功能的形状不同: 功能是"从无到有", bug 是"从错到对"。所以重点在**先复现、先找根因, 再动手**, 并且**修完一定要留记录**, 避免同一个 bug 反复回归、或者 ROADMAP 里的已知 bug 一直挂着没人勾掉。

严格按下面阶段推进, 每阶段结束用一句话报告再进入下一步。

## 阶段 0 · 复现 + 查已有记录

- 先在 `ROADMAP.md` 的已知 bug 段落搜一下: 这个 bug 是不是已经登记过、有没有旁注/线索。
- 翻 `CHANGELOG.md` 近期条目: 是不是最近某次改动引入的(回归), 缩小怀疑范围。
- 让用户或自己复现: 明确"什么操作 → 期望什么 → 实际什么"。复现不了就先问清复现步骤, 不要凭猜改代码。
- 涉及运行期行为时, `./build.sh` + `open build/LocalLrcPlayer.app` 实际操作一遍确认现象。

产出: 一句话写清"稳定复现路径 + 期望 vs 实际"。

## 阶段 1 · 定位根因(不要只治标)

- 顺着现象定位到具体文件/extension。常见落点: 播放/进度/歌词同步在 `PlayerWindowController_Playback`; 曲目表格/播放行样式在 `TrackListDataSource`; 歌词渲染滚动高亮在 `LyricsView`; 菜单栏歌词在 `MenuBarLyricsController`; 数据持久化在对应 repository。
- 分清"症状"和"根因"。例如"重启后高亮丢了"根因往往在持久化/恢复逻辑, 而不是渲染。
- 小心本项目的历史坑: FLAC seek 依赖 ffmpeg 转码缓存; macOS 26 菜单栏可见性权限; 受保护目录靠 Security-Scoped Bookmark 在重启后保持授权; 曲目按 SHA256 内容哈希去重。这些地方的"bug"可能是环境/权限而非逻辑错误, 先判断清楚。

产出: 一句话根因说明 + 打算怎么最小化修复。改动大或有多种改法时, 先跟用户对齐再动手。

## 阶段 2 · 最小修复

- 只改导致这个 bug 的代码, 别顺手重构无关部分(那属于 feature/simplify 的范畴)。
- 匹配周边风格(AppKit, 不用 SwiftUI)。
- 别破坏关键不变量: 数据库只做索引、`.lrc` 文件才是歌词真相、内容哈希去重。
- 数据安全红线(HANDOFF.md 明令): 不要删除或覆盖用户已有的本地音乐、歌词 `.lrc`、Cookie、缓存文件。

## 阶段 3 · 加回归测试(能测就必须测)

- 若 bug 在数据层(去重/播放列表排序/播放状态持久化/设置/迁移), 在 `Tests/RunDatabaseTests/main.swift` 加一个断言复现它, 确认改前会挂、改后通过。harness 是手写的 `assertEqual`/`assertTrue`, 末尾 `do{...}catch{exit(1)}` 作 runner。
- UI/播放这类难以自动化的 bug, 至少在阶段 4 用固定复现步骤手动验证, 并把步骤写进 HANDOFF 的验证清单。

## 阶段 4 · 构建 + 真机验证(硬约束)

没有热重载, 必须:

1. 退出正在运行的 App。
2. `./build.sh` 重新编译打包。
3. `plutil -lint build/LocalLrcPlayer.app/Contents/Info.plist` 校验 Info.plist(HANDOFF.md 验证清单要求)。
4. `open build/LocalLrcPlayer.app`, 按阶段 0 的复现路径走一遍, 确认现象消失。
5. `./test.sh` 跑一遍, 确保回归测试通过且没弄坏别的。

如实报告结果, 失败就贴输出, 不要嘴上说"修好了"而没实际验证。

## 阶段 5 · 登记记录(改 bug 的关键动作, 不能省)

本仓库 .md 不用 `**bold**`。今天日期从会话上下文取。遵循 HANDOFF.md 的文档分工:

- 把这个 bug 的条目从 `ROADMAP.md` 的 Known Bugs 段移到 `CHANGELOG.md` 的 Fixed 段(按日期, 摘要级: 修了什么、根因一句话)。这是 HANDOFF.md 规定的 bug 归档动作。
- 若这个 bug 之前没在 Known Bugs 里登记过, 直接在 `CHANGELOG.md` 的 Fixed 段按日期新增一条即可。
- 修复过程中发现的、本次不修的新 bug, 补登记到 `ROADMAP.md` 的 Known Bugs。
- 若修复改变了文档化的行为, 同步 `doc/database.md` / `doc/ui.md` / `README`。
- 不要把单个 bug 的复现步骤写进 `HANDOFF.md` —— 那里只放不会过期的协作流程, 不放具体 bug 记录。

## 收尾报告

按 HANDOFF.md 里的 Handoff Template 格式输出交接记录(本次目标 / 修改文件 / 实现内容 / 验证 / 文档更新 / 未完成风险), 不要另编格式 —— 交接格式的真相来源是 HANDOFF.md。根因、回归测试、构建/测试结果都如实写进对应栏。提交/推送只在用户明确要求时做。
