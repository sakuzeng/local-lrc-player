# Changelog

本文件记录 Local LRC Player 的重要修改，方便后续开发时回看变更背景。

## 2026-09-13

### Changed

- 菜单栏悬停卡片的出现与收起改为自绘动画:从右上角(贴着菜单栏歌词那一侧)按 0.6 倍展开并淡入(0.28s),
  曲线用的是歌词滚动那条带过冲的,落位时轻轻回弹;收起整块缩到 0.96 并淡出(0.15s)。
  关掉了系统的 `animationBehavior` 免得两层淡入叠加。
  缩放做在图层变换上而不是窗口尺寸上 —— 面板内容是固定宽度,改窗口尺寸会触发 Auto Layout 重排、动画里会抖;
  变换挂在毛玻璃外面新加的一层普通视图上,毛玻璃那层由 AppKit 管着不适合直接动。
  出现动画不 hold 终值,结束后自然归位;收起要 hold 住终值直到窗口真的隐藏,隐藏时清掉。
  动画可被打断 —— 收起途中再悬停会顶掉收起动画原地接回来,来回扫过菜单栏也不会一跳一跳;
  为此「显示中」的判定(`isShown`)排除掉正在收起的那一段。statusItem 重建与原生菜单弹出这类要立刻让位的场合不做动画。

### Added

- 音乐文件元数据写入(支持批量):把歌名、歌手、专辑、封面、歌词写进音频文件本身的标签,
  方便在其他播放器和设备上正确显示。曲目行右键「写入元数据…」写单首,文件菜单「为当前列表写入元数据…」
  批量写,运行中可「停止写入元数据」。仅 mp3 / flac / m4a;正在播放的那首跳过(AVPlayer 正握着文件句柄)。
  素材优先用本地已有的(文件名拆「歌手 - 歌名」、旁边的 `.lrc`、封面缓存),还缺才用歌词源搜一次;
  没配 Cookie 就纯本地补。
  三条安全约束:只补空着的字段(已有值一律不覆盖)、每个文件写前完整备份到 App 支持目录的 MetadataBackups、
  ffmpeg 流拷贝写临时文件成功后才原子替换(不重新编码)。写完 `TrackRepository.refreshAfterMetadataWrite`
  同步更新 `tracks.content_hash` 与 `tracks`/`library_tracks` 的 mtime/size,否则下次扫描会把它当成新曲目。
  备份有保留策略,不会无限堆积:同一首歌只留最新一份,写入任务结束后自动清掉超过 14 天或总量超 1 GB 的旧备份;
  文件菜单「元数据备份…」可查看占用、打开文件夹或全部删除。
  `MetadataWriterTests` 覆盖「只补缺失」判定、ffmpeg 参数构造,以及两条端到端用例(真实写入 + 读回 + 备份,
  写入后重新扫描仍是同一行同一 id)。

### Fixed

- FLAC 的标签一直读不出来,列表、菜单栏卡片、系统「正在播放」显示的都是文件名而不是真实歌名歌手:
  `TrackMetadataReader` 走 AVFoundation 的 `commonMetadata`,它读不了 vorbis comment(时长能读、标签全是 nil)。
  改为三项全空时退回 ffprobe 再读一次;`sync` 在跳过未变文件的分支里给标签全空的行补读一次
  (`refreshBlankMetadataIfNeeded`),否则这些行的 mtime 没变、永远停在空标签上。
  实测 30 首 FLAC 全部恢复出正确的歌名/歌手/专辑。

- 看自建播放列表时底部状态栏仍显示「共 55 首,6 首无歌词」这种音乐库总数,与只有几首的列表对不上:
  `statusSummary` 在非「全部」视图下先说当前列表几首,库的总数与无歌词数放括号里。

### Changed

- 播放态抽成 `NowPlayingModel`:窗口控制器是唯一写入方,在切歌、播放/暂停、seek 完成和 0.2s tick 时发布快照;
  菜单栏卡片改为只读快照、订阅变化,按钮和滑杆通过 `model.commands` 控制播放,不再拿着窗口控制器去调
  `xxxFromMenu` / `currentNowPlayingSnapshot()`,控制器→菜单栏→卡片的手工推送链随之去掉。
  系统「正在播放」仍由控制器直接喂(封面宽限、waiting 期覆盖是写入侧细节)。`NowPlayingModelTests` 覆盖
  发布/订阅/退订。`MenuBarLyricsView` 早已不在仓库,文档里的遗留说明一并清掉。

### Fixed

- 顺序/单曲循环模式下,最后一首按「下一首」原地重播、第一首按「上一首」也不动:`playNext` / `playPrevious`
  用 min/max 把索引钳在两端,而自动播完走的是「末首回第一首」。改为首尾循环(`wrappedIndex`),
  与自动切歌一致;随机模式不受影响。`TrackNavigationTests` 覆盖首尾与单曲、空列表。

### Added

- 无障碍:主窗口传输键、播放模式键、定位/播放列表/沉浸模式/音量按钮、进度条与音量滑杆、歌曲列表、歌词区,
  菜单栏卡片的四个按钮与两个滑杆,以及菜单栏状态项,都补了 accessibility label;播放键与模式键的标签随状态变,
  进度条用「已播/总长」时间做 value description,状态项把当前歌词行作为 value;封面和小喇叭标记为装饰不进
  VoiceOver 顺序。进度条本就是 NSSlider,获得焦点后方向键调值即 seek(`SeekSlider.keyDown` 走同一条提交路径),
  Tab 聚焦依赖系统「键盘导航」设置。`UILayoutTests` 新增卡片控件标签断言。

- 自建播放列表:列表顶栏的标题本身变成下拉按钮(「歌曲 · N ⌄」),弹出菜单在「全部」与自建列表间切换,并可新建 / 重命名 / 删除
  (「全部」是系统列表,不能改名删除);曲目行右键新增「加入播放列表 ▸」(按成员关系打勾,再点即移出,
  含「新建播放列表并加入…」),查看自建列表时另有「从当前列表移除」;文件菜单「新建播放列表…」(⌘N)。
  顶栏标题在自建列表时显示列表名,空列表有专门的空状态且顶栏保留以便切回。搜索和播放队列都在当前列表内生效。
  数据落既有的 `playlists` / `playlist_tracks`,无 schema 变更:`PlaylistRepository` 把总列表的查询与入列
  泛化为按 playlistId,新增 allPlaylists / create / rename / delete / addTrack / removeTrack / playlistIds(containing:)。
  当前列表记在 `player_state.current_playlist_id`(schema v8),重启后回到上次的列表,列表已删则回「全部」。
  `UserPlaylistRepositoryTests` 覆盖增删改查、去重、系统列表保护、
  曲目消失后自动退出自建列表。

- 播放队列第一期「接下来播放」:曲目行右键或「播放」菜单可把选中歌曲「下一首播放」(插队首)或
  「稍后播放」(追加队尾),另有「清空播放队列」。按「下一首」以及顺序/随机模式自动播完时优先出队;
  单曲循环自动播完仍循环本曲,只有手动「下一首」才走队列;随机模式下出队前照常记 shuffle 历史。
  出队按 id 再按路径在当前列表里找,找不到的(被搜索过滤、已删除)先跳过留在队列里。
  队列只在内存,退出即空;列表行副标题末尾显示「队列 N」,状态栏有临时提示。
  `PlayerWindowController_Queue`;`firstPlayable` 抽成纯函数并有 `PlayQueueTests`。

- 结构化日志与诊断导出:新增 `AppLog`(`os.Logger`,subsystem 为 bundle id,按 app / playback / library /
  lyrics / network / menubar / database 分 category),在既有失败分支旁落日志,不改行为:播放准备失败、
  歌词读取/解析失败、歌词源搜索与候选下载失败、未配置 Cookie、音乐库同步结果与失败、目录监听失败、
  菜单栏状态项重建、数据库打开。Cookie 值永不进日志。少量关键事件(同步结果、启动、歌词保存)用 notice
  持久化,`log show --predicate 'subsystem == "local.lrc.player.v2"'` 能查到;「开始播放」这类高频事件用 info,
  只在内存短期保留。
- 播放失败不再静默:`PlaybackController` 观察 `AVPlayerItem.status` 与 `AVPlayerItemFailedToPlayToEndTime`,
  文件损坏或格式不支持时状态栏显示「播放失败:…」并把播放键摆回,系统「正在播放」同步更新。
- 帮助 → 导出诊断信息…:`DiagnosticsReport` 把环境(版本、macOS、ffmpeg、数据库路径)、设置摘要、
  各音乐文件夹的存在/可读/上次同步、播放态、菜单栏歌词状态、最近 30 条歌词下载记录
  (`LyricLogRepository.recentAttempts`)和本进程的统一日志(`OSLogStore`,最多 400 条)拼成纯文本,
  经 NSSavePanel 保存后在 Finder 里选中。

- 测试补齐:`LrcParserTests`(时间戳格式、一行多时间戳、跳过元数据/空行、排序、同时刻多语言分组、
  `activeLineIndex` 边界与组内偏好中文)和 `UILayoutTests`(离屏布局回归:菜单栏卡片在有/无歌手、
  未播放等快照间复用切换后歌名块仍对着封面居中、空歌词行收起;歌词区当前行 26pt 粗体、邻行缩小、
  当前行居中于可视区;曲目列表播放行 semibold、普通行 regular、双行标签位置)。
  `test.sh` 改为编译 `Tests/RunDatabaseTests/` 下全部文件,`main.swift` 仍是唯一 runner。
  UI 测试在进程内起 `NSApplication` 用离屏窗口做 Auto Layout,不需要真机;
  断言优先复用同一实例做状态切换,因为新建视图往往是对的、复用后才会漂。


### Added

- 音乐库自动感知变化:每个已授权的音乐文件夹用一个 `DispatchSource` 盯目录项的增删/改名/替换
  (`LibraryFolderWatcher`),事件合并 2s 静默后触发一次增量 sync,sync 跑在后台队列不卡 UI,
  完成后回主线程刷新列表(`PlayerWindowController_LibraryWatch`)。同步进行中再来事件就排队再跑一轮;
  正在播放的文件被删则停止播放并清掉,与设置里移除文件夹一致。启动、添加/移除文件夹和每轮同步后
  都重新对齐监听集合,被拔掉又插回的卷会重新盯上。提示走 `showTransientStatus`,几秒后回填原状态。
  扫描只看顶层目录,所以目录级监听够用;文件内容原地改写不触发目录事件,但临时文件 + rename 的常见写法会。

- 系统「正在播放」集成:键盘媒体键(F7/F8/F9)、AirPods 捏合、控制中心与菜单栏的正在播放卡片
  都能控制本 App(播放/暂停、上一首/下一首、拖进度),卡片显示歌名/歌手/封面/进度。
  新增 `NowPlayingCenter` 封装 `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`,
  `PlayerWindowController_NowPlaying` 负责接线:切歌、播放/暂停、seek 完成时全量重发,
  0.2s tick 上只在播放态/时长/曲目信息变化或进度外推漂移超过 1.5s 时才重发。
  远程「播放」只继续当前曲目,不会像空格那样跳到列表选中行(`resumeCurrentTrack` / `pauseCurrentTrack`)。
  `build.sh` / `test.sh` 新增链接 MediaPlayer 框架。
  切歌后给封面 0.4s 宽限:内嵌封面是异步读的,先发无封面信息系统卡片会闪一下 App 图标,
  宽限内没封面就先不发(卡片多停留一拍在上一首),封面一到或到期即发。
  歌手标签为空时按「歌手 - 歌名」拆开给系统,与列表和悬停卡片一致。

## 2026-09-10

### Fixed

- 菜单栏卡片切到没有歌手标签的歌(如文件名当歌名的 mp3)时,歌名贴到封面顶端甚至顶出卡片,
  切回有歌手的歌时歌名/歌手也整体偏上:封面与文字块用横向 `NSStackView` 的 `centerY` 对齐,
  歌手行显隐切换改变文字块高度后 stack 不再重新居中,文字块贴到顶部。新建的卡片没这个问题,
  只有常驻复用的卡片在快照切换时出现。修复:封面与文字块改用显式约束(文字块 centerY 对齐封面),
  不再依赖 stack 对齐。

## 2026-09-09

### Fixed

- 歌词区拖选文字后留下一块蓝色选区,点别处也去不掉:歌词 `NSTextView` 开着 `isSelectable`,
  拖动就产生选区,失焦时 AppKit 只把它画成非强调色、不会清掉。歌词区的语义是点行 seek,
  不需要选文字,改为不可选,选区不再产生;点行 seek 走 `NSClickGestureRecognizer`,不受影响。

### Changed

- 菜单栏悬停卡片去掉小三角,改成挂在菜单栏下方、右缘对齐歌词右缘的圆角面板(照系统控制中心下拉的样子)。
  原先是 `NSPopover`,箭头指向 button 中心,状态项从右往左排、`item.length` 随歌词变化时
  右缘不动左缘伸缩,箭头就跟着来回漂;`NSPopover` 又没有公开 API 去掉箭头。
  现在用 borderless + nonactivating 的 `NSPanel` 装同一个卡片视图,`.popover` 材质毛玻璃底 14pt 圆角,
  0.2s 刷新链里重算位置,卡片弹出期间歌词换行或歌词行显隐也保持右缘对齐;右侧超出屏幕时整体左移。

## 2026-08-26

### Fixed

- 深色模式下歌词整体显示成浅色外观的黑字,拖动进度条跳转后又变回白字:
  换行动画每帧用 `blended(withFraction:)` 插值,把动态语义色拍平成静态色,
  而 Timer 回调的默认绘制外观是浅色,动画结束后写进 textStorage 的全是浅色解析的黑字;
  跳转路径(`applyLineStyles`)用的是动态色,才会一拖就"变白"。
  修复:动画帧在视图 `effectiveAppearance` 下解析,动画收尾再用动态色重写一遍,
  让静止状态继续跟随外观切换。App 只有浅色时此 bug 一直存在但不可见。

## 2026-08-23

本日:外观切换(跟随系统/浅色/深色);菜单栏悬停卡片歌词行改版。

### Added

- 外观设置:⌘, 设置新增「外观」分组,三档 跟随系统/浅色/深色,切换立即生效并持久化
  (`app_settings.appearance`,schema v7)。启动时先应用外观再建窗口,避免闪默认外观。
  界面本就全部使用语义色,主窗口/设置窗/弹窗/悬停卡片随 `NSApp.appearance` 一起变;
  菜单栏歌词位图与浅色菜单维持现状(属菜单栏体系,见 `doc/ui.md`)。

### Fixed

- 浅色模式下拖动进度条,预览时间气泡显示成深底黑块:建视图时把
  `controlBackgroundColor.withAlphaComponent(0.9).cgColor` 拍平成了静态色,
  外观切换后不再跟随。改为每次显示气泡时按 `effectiveAppearance` 重新解析
  (`doc/ui.md` 早有记录的 CGColor 拍平坑,运行时外观切换让它必现)。

### Changed

- 歌词当前行高亮从系统强调色(蓝)改为 `labelColor`(深色纯白/浅色近黑),
  学 Apple Music 靠字号字重区分当前行——大字块的高饱和蓝压在氛围背景上太突兀。
- 列表播放行标题同样从强调色改为 `labelColor`,靠强调色行底 + semibold 识别正在播放;
  行底色、进度条、播放模式图标的强调色保持不变。
- 菜单栏悬停卡片:当前歌词从歌名歌手下的第三行改为单独一行、整卡居中,
  字号 12pt 主文字色;歌词为空时该行自动收起不留空白。

## 2026-08-03

本日:菜单栏歌词悬停弹出正在播放卡片;主窗口沉浸模式。

### Added

- 沉浸模式（⌘⇧F / 列表顶栏展开按钮 / 视图菜单，Esc 或右上角收起按钮退出）：
  藏起整个 splitView，换成左侧大封面 + 右侧歌名歌手与放大左对齐歌词 + 底部一整行播放控制。
  容器是 splitView 的兄弟节点、互斥显隐，日常布局零改动；约束全部落在容器内部，
  不碰 split 列宽（`doc/ui.md` 记着这条会导致启动约束崩溃的旧账）。
  不造第二套控件——`lyricsView` / `transportRow` / `progressRow` 在两套容器间搬家，
  跨视图约束收成两组，切换顺序固定为 卸当前组 → 搬视图 → 装目标组。
  大封面按内容区宽度取 40%，同时受 460pt 上限与内容区高度压制，窄窗矮窗都不会顶穿控制区。
  歌词排版新增 `LyricsDisplayProfile`（日常 26/18pt 居中，沉浸 34/22pt 左对齐，行高随字号一起放大）。
  状态不持久化，启动总是日常模式：省掉 schema 迁移，且启动时封面尚未就绪，沉浸首屏会是空封面。

- 菜单栏悬停正在播放卡片（`MenuBarNowPlayingCard.swift`）：停在菜单栏歌词上 0.3s 弹出 320pt 卡片
  （48pt 封面 + 歌名/歌手/当前歌词 + 可拖动进度条与两端时间 + 上一首/播放暂停/下一首 + 播放模式 + 音量），
  指针离开 button 与卡片 0.25s 后收起；点击仍走原有原生菜单，菜单打开期间抑制卡片。
  tracking area 挂在 `statusItem.button` 上（owner 回调，`.inVisibleRect` 应对歌词滚动导致的宽度变化，
  statusItem 重建时按 button 身份幂等重挂）；刷新挂在既有的 0.2s 推送链上，卡片没弹出时零开销，不新开 timer。
  控件全是新实例并 `acceptsFirstMouse`——卡片弹出时 App 通常在后台，否则第一次点击只会激活 App 被吞掉。
  控制回调复用 `*FromMenu` 与 `cyclePlaybackMode`，另新增 `seekFromRemote` / `setVolumeFromRemote`；
  前者走 `seekToLyricLine` 那条干净路径，不碰主窗口滑杆的 `isSeekingWithSlider` / `seekGeneration` 状态机。
  第一期不加独立设置开关，随「在菜单栏显示歌词」总开关一起生效。
  已知限制：多显示器下只有当前聚焦那块屏的菜单栏悬停会弹卡片（`NSStatusItem` 只有一个 button window，
  另一块屏是系统镜像，收不到 tracking 事件），点击菜单两块屏都可用。

- 播放里程碑（schema v5）：某首歌的有效播放次数命中 10/50/100/300/500/1000 时，
  等这首播完或被切走再弹庆祝面板（大封面 + 数字滚动计数 + 首播至今天数），
  面板底色与大字取自封面主色，复用 `AmbientBackgroundView` 那套取色（提到 `ArtworkColor` 共用）。
  有效播放沿用 Last.fm 的 scrobble 规则：曲长 > 30 秒且实际听满一半或 4 分钟（取较小者）；
  判定累加 tick 里的真实播放秒数而非 `currentTime`，拖动进度条骗不过去，跳过的播放不计数。
  `play_history.counted` 区分「开始播放」与「有效播放」，迁移给历史行留默认 0，
  里程碑因此从功能上线后重新起算 —— 否则一批老歌会在首次启动时集体弹窗。
  面板是 borderless `NSPanel` + `nonactivatingPanel`，不抢 App 焦点但重写 `canBecomeKey` 让 Esc/回车可用。

- 往年今日（schema v6）：启动同步完音乐库后回顾同一天听过的歌，每天最多一次。
  偏移量按 12 → 6 → 3 → 1 个月依次取第一个有记录的跨度 —— 现在只可能命中 1 个月，
  等历史攒够一年，同一段代码自己变成真正的「往年今日」，文案也自动从「1 个月前」变成「1 年前」。
  月份回推走 `Calendar` 而非减固定秒数（3 月 31 日减一个月是 2 月 28 日，减 30 天会落到 3 月 1 日）。
  那天没有记录就安静，不弹空窗；去重靠 `app_settings.last_memory_shown_on`。
  与里程碑共用同一个面板，内容抽成 `CelebrationContent`；两类提醒各有独立开关，
  设置窗口新增「播放里程碑」一节，弹窗里的「不再提醒」按类型分流。

### Fixed

- 状态栏一次性提示会一直占着不走（切显示模式后尤其明显，除非播放状态变化才被顶掉）。
  根因是把操作反馈塞进了承载持续状态的 `statusLabel`（正在播放某首、共多少首）。
  新增 `showTransientStatus`：3 秒后回填原状态，期间若已被别的消息覆盖就不再回填；
  连续触发多条提示时回填目标始终是最初那条持续状态，而不是上一条提示。
  切模式、定位、进入沉浸模式三处改走它；退出沉浸模式不再发提示（布局变化本身已足够明显）。

### Changed

- 菜单栏 status button 不再设 `toolTip`：系统气泡会叠在卡片上方重复同一句歌词，
  改由卡片第三行显示完整当前行（菜单栏截断时也能看全）。
- 「歌手 - 歌名」拆分逻辑从 `TrackListDataSource` 的私有实现提到 `MusicTrack.parseArtistTitle`，
  曲目列表与菜单栏卡片共用；ID3 缺歌手时卡片也能拆出副标题，不再整串挤在标题行。

## 2026-07-31

本日:修复播放中在 Finder 改文件名后刷新导致播放行错位/播放状态写错曲目/进度条越界崩溃。

### Fixed

- 播放中在 Finder 里给歌曲改名，再点刷新后一系列错乱（列表没有任何行高亮成播放行、
  菜单栏歌词显示成别的歌、`player_state` 被写成别的歌的 id、拖动进度条可能崩溃）。
  根因是窗口层只用文件路径（`playingTrackURL`）认「正在播放」，改名后路径失配，
  `currentTrackIndex` 原样留着变成悬空索引，指向重排后列表里的另一首歌；
  列表因搜索过滤或同时删文件而变短时，这个索引还会越界。
  数据层本身没问题：SHA256 内容哈希去重会把改名后的文件认成同一首，
  track id 不变、`tracks.file_path` 与 `library_tracks` 重指新路径，
  只有 `playlist_tracks.sort_order` 按新文件名重排（所以列表位置会变）。
  修法是新增 `playingTrackId`，刷新后按路径找不到就按 track id 把播放行认回来并纠正路径，
  彻底认不回来才清空 `currentTrackIndex`（不再留悬空值）；
  播放状态落库改为以 `playingTrackId` 为准，不再从索引取 id；
  `completeSliderSeek` 补上越界检查。数据库测试新增改名后 track id 稳定/路径重指的断言。

## 2026-07-08

本日:设计并接入正式 App 图标;播放区信息补全(封面/歌名/歌手 + 封面下载缓存);音量控制(schema v4);歌词点击 seek 与排版升级;ROADMAP 登记界面美化第二阶段与音乐文件元数据写入计划。

### Added

- 正式 App 图标：靛蓝→紫渐变圆角方形 + 白色音符 + 三条歌词线（中间当前行高亮）。
  `assets/render_app_icon.swift`（CoreGraphics 一次性渲染脚本）→ `assets/AppIcon-1024.png`
  → `assets/make_icns.sh`（sips 降采样 + iconutil）→ `assets/AppIcon.icns`；
  `build.sh` 拷贝 icns 进 Resources 并在 Info.plist 写入 `CFBundleIconFile`。
- 播放区正在播放信息：进度条行左侧 36pt 圆角封面 + 歌名/歌手双行（`PlayerWindowLayout.updateNowPlaying`）。
  封面优先读内嵌图（`TrackMetadataReader.artworkData`）；无内嵌图时复用歌词搜索评分挑最可靠候选下载专辑图
  （网易云 song/detail picUrl / QQ albumMid 图床），只写 `~/Library/Caches/LocalLrcPlayer/Artwork/`
  （`ArtworkCache` + `ArtworkDownloadService`），不修改音频文件；每曲目每次运行只自动尝试一次，静默失败。
- 音量控制：进度条行右端音量滑杆；`PlaybackController.volume` 播放重建时套用；
  `player_state.volume`（schema v4 迁移）持久化，拖动防抖落库；数据库测试补默认值/持久化/越界钳制断言。
- 点击歌词行 seek：`LyricsView.onLineClicked` 按行高命中回调行时间；已加载即 seek，未加载记为恢复位置。

- 主题色氛围背景（`AmbientBackgroundView`）：封面 1x1 下采样取平均色（拉饱和度、压亮度后使用），
  毛玻璃上叠左上/右下两团色相微错开的大半径 radial 色斑，切歌 1.2s 交叉淡入淡出；无封面淡出回纯毛玻璃。

- 进度条悬停反馈：hover/拖动时轨道 4→6pt、圆点放大，指针位置显示 mm:ss 时间气泡并跟随移动
  （`SeekSlider.onHoverFraction` → 控制器按时长换算 → `PlayerWindowLayout.showSeekPreview`）。

### Fixed

- 歌词行切换抖动/不流畅（当日排版升级引入的回归）：字号插值逐帧改变行高导致全文 reflow、
  滚动目标中途漂移。改为段落固定行高 40pt（min=max）+ baselineOffset 垂直居中，
  行间空行 `\n\n` 改 `paragraphSpacing 14`；字号动画只放大字形，不再引起布局抖动。

### Changed

- 歌词当前行排版升级：22pt semibold → 26pt bold，行距 10 → 12（后改为固定行高 40 + 段后距 14，见 Fixed）。
- 歌词滚动动画改为带轻微过冲的 spring 曲线（0.5s，控制点 0.2/1.12/0.35/1.0）。
- 无曲目时歌词顶栏高度收到 0（原来隐藏但保留 48pt 空白）。
- 正在播放信息块最终落位歌词区顶部（`nowPlayingBar`，水平居中，无曲目时隐藏）；
  进度条行改为 进度条 + 时间 + 喇叭按钮，音量为点喇叭弹出的竖向 popover 滑杆
  （`isVertical = true`，仅靠约束高宽比不生效）。

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
