# Local LRC Player 文档

本目录存放项目设计与实现说明，便于后续维护、修 bug 和扩展功能。

## 文档索引

| 文档 | 说明 |
|---|---|
| [database.md](./database.md) | SQLite 数据库：文件位置、表结构、主键/外键、索引、读写流程、迁移策略 |
| [ui.md](./ui.md) | 主窗口布局、NSToolbar 分段与间隔、列表顶栏与播放区 UI 约定 |

## 维护约定

- 修改 `AppDatabase.swift` 中的 schema 或 Repository 行为时，**同步更新** `doc/database.md`。
- 修改主窗口工具栏、列表顶栏、播放区布局时，**同步更新** `doc/ui.md`。
- 在 `CHANGELOG.md` 的 `Changed` 或 `Added` 中简要提及 schema 版本变更。
- 歌词正文、音频文件、Cookie **不写入数据库**；数据库只存索引、状态与审计 log。
