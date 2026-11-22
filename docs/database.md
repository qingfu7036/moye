# MOYE 数据库设计（schema v5）

本文记录 Phase 1 已落地的 SQLite 结构、路径规则和数据一致性约束。它是 V1 的起点，不是最终完整 schema；后续章节（笔记、会话、统计、附件）通过**追加迁移**实现，禁止修改已经发布的迁移。

## 1. 技术选择与版本

| 平台 | SQLite 来源 | 说明 |
|---|---|---|
| Windows 10/11 | `package:sqlite3` 3.8.0 原生资产 | 通过 Dart native assets hook 加载，测试与桌面构建已通过 |
| Android | `eu.simonbinder:sqlite3-native-library:3.50.4` AAR | 通过 Gradle 依赖打包 `libsqlite3.so`；`sqlite3` hook 在 Android 上使用 `source: system`，由 APK 内的 `libsqlite3.so` 提供符号 |
| 测试 | 同一 `package:sqlite3` API | 单元测试使用同一 schema 与 SQL |

Android 的原生库来源在 `android/app/build.gradle.kts` 中固定为 Maven 坐标 `eu.simonbinder:sqlite3-native-library:3.50.4`，`pubspec.yaml` 中对应配置为：

```yaml
hooks:
  user_defines:
    sqlite3:
      source:
        android: system
        default: sqlite3
```

这样 Android 构建不需要访问 GitHub 下载预编译 `.so`，Windows 仍使用 native assets hook。APK 中三个 ABI 都包含 `libsqlite3.so`：

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

> 这是 Phase 1 的构建兼容方案。后续如果升级 `sqlite3` 到不再支持 `source: system` 的版本，或需要 SQLCipher/自定义编译选项，应改为 vendored SQLite amalgamation + `source: source`，并重新做 Android 运行验证。

## 2. 数据库位置与目录布局

`AppPaths` 只保存**相对于应用私有根目录**的路径，绝不把绝对路径写入数据库。这样 Windows 与 Android 的备份恢复不需要做路径重写。

Windows 实测根目录：

```text
%APPDATA%\app.moye\moye\
├── database\library.db
├── books\
├── covers\
├── attachments\
├── cache\trash\
├── backups\
└── logs\
```

Android 使用 `path_provider` 返回的应用私有目录，布局相同。数据库存储 `books/<uuid>.pdf` 这类 POSIX 相对路径；`AppPaths.resolveRelative` 会拒绝绝对路径、`..` 和 canonicalize 后越出根目录的路径。

SQLite 打开参数：

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
```

WAL 提升读写并发，但也意味着**不能直接复制正在使用的 `library.db` 文件做备份**。Phase 5 的 `.moye` 备份必须先执行 WAL checkpoint，或使用 SQLite 的在线 backup API；恢复时也要处理 `-wal`/`-shm` 文件。

## 3. schema v5（含历史表）

迁移版本常量：`librarySchemaVersion = 5`，定义在 `lib/core/database/migrations.dart`。

### 3.1 `books`

| 列 | 类型 | 约束 / 含义 |
|---|---|---|
| `id` | TEXT | UUID v4 主键，稳定唯一 |
| `title` | TEXT | 非空，元数据或文件名 |
| `author` | TEXT | 默认空串 |
| `format` | TEXT | `pdf` / `epub` / `docx` / `doc` / `txt` / `markdown` |
| `original_file_name` | TEXT | 用户导入时的原始文件名，用于展示与追溯 |
| `relative_path` | TEXT | 相对应用根目录，UNIQUE |
| `file_hash` | TEXT | SHA-256，UNIQUE，用于重复书籍识别 |
| `file_size` | INTEGER | 字节数，CHECK >= 0 |
| `cover_path` | TEXT | 相对路径 `covers/<bookId>.jpg`；导入时从书籍提取，旧书启动后补齐 |
| `status` | TEXT | `notStarted` / `reading` / `paused` / `finished` / `reread` |
| `added_at` | INTEGER | UTC 毫秒 |
| `updated_at` | INTEGER | UTC 毫秒 |
| `last_opened_at` | INTEGER | UTC 毫秒，可空 |
| `metadata_source` | TEXT | `epub_opf` / `docx_core` / `file_name`（PDF 暂回退文件名） |

索引：书名（NOCASE）、作者（NOCASE）、状态、导入时间倒序、最近打开时间倒序。

### 3.2 书架与标签

- `shelves(id, name, sort_order, created_at)`
- `book_shelves(book_id, shelf_id, added_at)`，联合主键，两个外键均为 `ON DELETE CASCADE`
- `tags(id, name UNIQUE, color, created_at)`
- `book_tags(book_id, tag_id, added_at)`，联合主键，两个外键均为 `ON DELETE CASCADE`

Phase 1 UI 尚未提供书架/标签管理；表和约束先落地，后续直接接 UI。

### 3.3 `reading_progress`

```text
book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE
anchor_json TEXT
percent REAL CHECK (0..1)
mode TEXT
updated_at INTEGER NOT NULL
```

`anchor_json` 保存阅读定位。PDF 写入 `{"page": N}`，`mode` 为 `pdf`；EPUB 写入 `{"chapter": N, "block": N, "cfi": "..."}`，`mode` 为 `epub`。DOCX 的定位结构在后续阶段补充。Phase 1 导入时创建 0% 的初始记录。

### 3.4 `settings`

`key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL`。用于非敏感、可备份的用户设置；数据库不存密码/令牌。

### 3.5 `annotations`（schema v2，v5 支持孤立标记）

区域标记/备注仓库：

| 列 | 类型 | 含义 |
|---|---|---|
| `id` | TEXT | UUID 主键 |
| `book_id` | TEXT | 外键 `books(id) ON DELETE CASCADE` |
| `kind` | TEXT | 当前为 `region` |
| `page_number` | INTEGER | PDF 页码 |
| `chapter_index` | INTEGER | EPUB 章节索引 |
| `block_index` | INTEGER | EPUB 章内块索引 |
| `rect_json` | TEXT | 归一化矩形 `{left,top,width,height}`，相对阅读可视区域 |
| `note` | TEXT | 用户备注 |
| `quote` | TEXT | 可选原文引用 |
| `image_path` | TEXT | 截取区域 PNG，位于 `attachments/annotations/<id>.png` |
| `color` | TEXT | 默认 `yellow` |
| `created_at` / `updated_at` | INTEGER | UTC 毫秒 |

索引：`(book_id, created_at DESC)`、`note`（NOCASE）。按备注/引用搜索使用参数绑定的 `LIKE ... ESCAPE '!'`。

### 3.6 `speech_progress`（schema v3）

朗读位置与阅读位置分开保存：

```text
book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE
anchor_json TEXT NOT NULL
percent REAL CHECK (0..1)
mode TEXT NOT NULL
updated_at INTEGER NOT NULL
```

PDF 写入 `{"page": N, "offset": 0.0}`，EPUB 写入 `{"chapter": N, "block": N, "cfi": "..."}`。当前最小 TTS 在朗读位置变化时保存，暂不自动跳转回上次朗读位置。

### 3.7 `bookmarks`（schema v4）

```text
id TEXT PRIMARY KEY
book_id TEXT REFERENCES books(id) ON DELETE CASCADE
page_number INTEGER
chapter_index INTEGER
block_index INTEGER
page_offset REAL
label TEXT
created_at INTEGER
```

PDF 书签记录页码和页内偏移；EPUB 书签记录章节和块索引。同一位置重复添加会复用已有书签。

schema v5 起，`annotations.book_id` 可为空，并保存 `book_title` 快照；删除书籍时选择“保留标记”会让标记留在跨书知识仓库，截图不删除。

### 3.8 尚未落地的表

- `notes`（独立笔记）、`attachments`：后续阶段
- `reading_sessions`：Phase 5 统计
- 全文搜索 FTS 表：Phase 2/3，根据引擎确定后再建

## 4. 导入流程与一致性

`LibraryRepository.importFile` / `importStream`：

1. 按扩展名判定格式；不支持时返回 `unsupported`，不写入书库。
2. 把源文件复制到 `books/.import-<uuid>.part`，边写边计数。
3. 对临时文件计算 SHA-256。
4. 用 `file_hash` 查重：
   - 已存在：删除新副本，返回 `duplicate`，不新增卡片。
   - 不存在：把临时文件原子 rename 为 `books/<uuid>.<ext>`。
5. 读取元数据（EPUB OPF、DOCX core.xml；PDF 及其他格式回退文件名）。
6. 在单个 SQLite 事务中插入 `books` 和初始 `reading_progress`。
7. 任一步失败：删除临时文件/已复制文件，返回 `failed`，不留下半条记录。

关键点：**先落文件，再落数据库**；数据库事务失败时清理文件。重复文件会短暂产生新副本，查重后立即删除，因此最终只保留一份；如果进程在“rename 完成、查重删除”之间崩溃，`books/` 可能留下一个无数据库记录的孤儿文件，后续清理任务需要处理。若数据库行存在但原文件缺失，重新导入会复用该行并挂接新副本，而不是丢弃新副本。

## 5. 删除流程

1. 读取 `relative_path`。
2. 把书籍文件 rename 到 `cache/trash/<bookId>.<ext>`（quarantine）。
3. 在事务中删除 `books` 行；外键级联删除进度、书架/标签关联。
4. 事务成功后才 best-effort 删除 trash 文件；trash 被占用不会让已完成的删除失败。
5. 事务失败则尝试把文件 restore 回 `books/`，保留数据库行；restore 失败时保留原始数据库错误。
6. 应用启动时 `LibraryRepository.reconcileQuarantine()` 扫描 trash：数据库行仍存在且 `books/` 文件缺失 → 恢复；数据库行不存在 → 清理残留。

这个顺序优先保证“数据库和可见文件不出现一半状态”。极端情况下仍可能留下 trash 或孤儿文件，启动恢复只覆盖“数据库行存在、文件在 trash”的窗口。

## 6. 迁移规则

- `PRAGMA user_version` 记录 schema 版本。
- 打开时如果数据库版本高于应用支持版本，立即拒绝打开，防止旧程序写坏新库。
- 迁移在 `BEGIN IMMEDIATE` 中逐版本执行；失败回滚并抛出 `DatabaseException`。
- 已发布的迁移不可修改；新增变更追加到 `libraryMigrations` 并提升 `librarySchemaVersion`。
- 正式发布前必须对“从每个历史版本升级”和“备份恢复后迁移”做测试。

## 7. 测试覆盖（Phase 1）

`test/database_test.dart` 的 27 个测试使用真实样书和临时目录验证：

- schema v5 建表、外键开启
- 真实 PDF 导入、复制、SHA-256、初始进度
- PDF 第一页 / EPUB OPF 封面 / DOCX 首个内嵌图片的封面提取
- PDF 页码进度保存、关闭重开后恢复
- EPUB 章/块锚点、CFI 与设置持久化
- `speech_progress` 独立朗读位置持久化
- 书签去重、查询和删除
- 删除书籍时保留区域标记（`book_id=NULL` + 书名快照）
- EPUB / DOCX 元数据优先于文件名
- 重复内容识别并删除重复副本
- 不支持扩展名不写文件；不支持的流不创建缓存文件
- 读取中断后清理缓存临时文件
- 状态过滤与 LIKE 通配符/转义搜索
- 删除书籍行、进度和私有文件
- 路径穿越拒绝
- 关闭/重开数据库后持久化
- 数据库版本高于应用支持版本时拒绝打开
- 隔离后崩溃的启动恢复
- 缺失原文件的重复导入修复

Windows 真实 UI 集成测试还验证了导入 → 卡片 → 详情 → 删除的完整链路，见 `docs/phase-1/PHASE_1_REPORT.md`。

## 8. 封面

封面由 `BookCoverExtractor` 生成，统一写入 `covers/<bookId>.jpg`：

- PDF：渲染第一页（640px 宽），不是书名首字。
- EPUB：优先 `properties="cover-image"`，其次 EPUB2 `<meta name="cover">`，再其次 guide 的 cover reference。
- DOCX：读取 `word/media/` 中首个位图；没有位图则回退排版封面。
- TXT / Markdown / DOC：没有可靠首页图像，使用完整书名/作者的排版封面，不再使用首字。
- 提取失败、加密 PDF、扫描件或 SVG 封面回退排版封面；导入不会因封面失败而失败。
- 删除书籍时同时删除封面；旧书通过 `backfillMissingCovers()` 在书库页面异步补齐。

## 9. 已知限制

- 尚无 FTS5 索引；当前搜索是 `LIKE`，对 100 本书规模足够，规模上来后需评估 FTS5。
- 区域标记已实现；独立笔记、书签和附件管理仍属于后续阶段。
- Android APK 已构建并检查 `libsqlite3.so` 符号，但当前主机无真机/可用模拟器，**Android 运行期数据库打开尚未验证**。
- Windows 首次从零构建时 `package:sqlite3` 可能需要下载其原生 DLL；本机已缓存。发布流水线应固定缓存或改为自编译 SQLite。
- 元数据解析对 EPUB/DOCX 使用 `readAsBytes()` + `ZipDecoder`，大文件有内存峰值；导入没有显式大小上限，这些是 Phase 2 前需要补的边界测试。
- 启动恢复只处理 trash 中的文件；`books/` 中无数据库记录的孤儿文件尚未自动清理。
