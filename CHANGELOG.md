# Changelog

## [1.4.0-annotations] - 2026-11-06

### Added

- PDF/EPUB 阅读器新增右下角“标记区域”浮标。
- 框选矩形后截取该区域为 PNG，并填写备注。
- 区域标记保存到本书仓库：备注、原文引用（可选）、页码/章节、截图和时间。
- 本书详情新增“本书标记与备注”入口；支持按备注/摘录搜索。
- 阅读器内重新打开时显示已保存的标记框，点击可查看截图和备注。
- SQLite schema v2 新增 `annotations` 表，外键级联删除；截图写入 `attachments/annotations/`。
- 区域截取、创建/搜索/删除、EPUB 与 PDF 截图流程均有测试。

### Verified

- 26 个单元/Widget 测试通过。
- PDF/EPUB 区域标记集成测试通过：框选、截图、备注、本书仓库搜索、阅读器标记框。
- Windows 构建通过；Android APK 构建通过，运行仍未验证。

## [1.3.2] - 2026-11-06

### Fixed

- EPUB 阅读器增加明确的“上一页 / 下一页”按钮和段落位置指示。
- 修复 EPUB 短章节中滚轮/触控板看起来“无法翻页”的问题：现在可翻到下一段/下一章。
- 当前段落随滚动实时更新，便于确认位置。

## [1.3.1] - 2026-11-06

### Fixed

- EPUB 第一章节可能是空的 `titlepage.xhtml`，之前会显示空白；现在自动跳到第一个有文字的章节。
- EPUB 返回按钮之前会被位置保存异常卡住；现在保存失败也保证返回书库。
- 空章节不再参与章节位置写入，避免 `clamp(0, -1)` 异常。
- 用真实 149 章 EPUB 回归测试验证：空 titlepage 自动跳过、TOC 可用、能返回书库。

## [1.3.0-epub] - 2026-11-06

### Added

- Phase 2 EPUB 阅读切片：自建 EPUB 解析器、章节目录、章节切换。
- EPUB 字号、行距、背景主题设置，并持久化到 `settings` 表。
- EPUB 章/块/CFI 锚点保存与恢复；返回书库刷新最近阅读时间。
- 自建解析器不依赖 WebView，Windows 与 Android 共用同一套 Dart 渲染路径。
- EPUB 集成测试：打开、TOC、返回书库、锚点持久化。

### Verified

- 24 个单元/Widget 测试通过。
- `pdf_reader_test`、`epub_reader_test`、`phase1_library_test` 三组 Windows 集成测试通过。

### Known limitations

- 当前 EPUB 渲染器是阅读切片，尚未完成生产引擎对比；CSS、脚注、ruby、复杂表格、跨节点 CFI 不完整。
- DOCX 阅读器按用户范围决定不做；DOCX 仍可导入。书内搜索、标注仍未实现。
- Android 运行仍未验证。

## [1.2.1] - 2026-11-06

### Fixed

- 阅读器返回书库后立即刷新书籍列表，修复“最近阅读”时间仍显示旧值的问题。
- 最近阅读时间现在由阅读器打开/翻页/关闭时写入，并在返回书库时刷新展示。
- 明确阅读状态为手动设置：打开阅读器不会自动改“正在阅读/已读完”等状态。

### Verified

- 22 个单元/Widget 测试通过。
- 数据库测试断言 `last_opened_at` 为当前时间且状态保持 `notStarted`。
- PDF 阅读集成测试、Phase 1 书库集成测试通过。

## [1.2.0-reader] - 2026-11-03

### Added

- Phase 2 第一切片：PDFium PDF 阅读器，支持缩放/滚动、页码显示、从详情进入阅读。
- 阅读位置保存到 `reading_progress.anchor_json`（`{"page": N}`），重新打开恢复页码。
- 阅读器返回书库前保存最后位置；阅读状态与最近打开时间更新。
- Windows 集成测试验证：打开 PDF、恢复第 2 页、返回书库。
- 21 个单元/Widget 测试与 2 组 Windows 集成测试通过。

### Verified

- `flutter test`：21 个测试通过。
- `phase1_library_test`：1/1 通过。
- `pdf_reader_test`：1/1 通过，PDF 在保存的第 2 页打开并返回书库。

### Known limitations

- EPUB/DOCX 阅读器尚未实现；详情页只对 PDF 显示“开始阅读”。
- 当前只保存页码，不保存页内滚动偏移；连续滚动位置将在后续细化。
- Android 运行仍未验证。

## [1.1.0-cover] - 2026-11-03

### Added

- 真实封面提取：PDF 渲染第一页，EPUB 读取 OPF/EPUB2 封面，DOCX 读取首个内嵌位图。
- 封面统一压缩为 `covers/<bookId>.jpg`；删除书籍时删除封面。
- 旧书启动后通过 `backfillMissingCovers()` 异步补齐封面。
- 无封面格式（TXT/Markdown/DOC）改为完整书名/作者排版封面，不再显示书名首字。
- 20 个单元/Widget 测试（当时）与 Windows 集成测试覆盖封面生成、显示和删除。

### Verified

- PDF/EPUB/DOCX 封面文件均生成并通过 `>500 bytes` 校验。
- Windows 集成测试验证导入后卡片出现图片、删除后封面文件消失。

## [1.0.0-phase1] - 2026-11-03

### Added

- Phase 1 Flutter 应用骨架（Windows / Android）、Riverpod 注入、go_router 路由、Material 3 明暗主题与中文本地化。
- SQLite schema v1、版本化迁移、外键、WAL 与事务封装。
- 应用私有目录布局、相对路径安全解析、书籍文件复制与 SHA-256 去重。
- PDF / EPUB / DOCX / DOC / TXT / Markdown 导入；PDF/EPUB/DOCX 元数据提取。
- 书库页面：网格/列表、搜索、状态筛选、排序、导入进度、书籍详情、状态修改、删除确认。
- 阅读进度初始化；删除时文件隔离与失败恢复；启动时恢复隔离区中的书籍文件。
- 缺失原文件的重复导入修复；边复制边计算 SHA-256；不支持的流在落盘前拒绝。
- 15 个数据库/仓库测试、4 个 Widget 测试、Windows 真实 UI 集成测试。
- Phase 1 验收报告与数据库设计文档。
- Android 构建使用 Maven Central `sqlite3-native-library` 提供三套 ABI 的 `libsqlite3.so`，绕开本机 GitHub 下载阻塞；`abiFilters` 固定为 `arm64-v8a` / `armeabi-v7a` / `x86_64`。

### Verified

- `dart analyze lib test integration_test`：No issues found。
- `flutter test`：19 个测试通过。
- Windows 集成测试：真实 PDF 导入、持久化重开、详情删除通过。
- Android debug APK 构建通过，三套 ABI 均含 `libsqlite3.so`/`libflutter.so`；`zipalign -P 16` 通过，64 位 SQLite 库 LOAD 对齐为 `0x4000`。

### Known limitations

- Android 运行未验证：无真机，模拟器硬件虚拟化不可用，ADB server 挂起。
- 中文仓库路径导致 Android Gradle/NDK 构建失败；当前依赖 ASCII 构建副本。
- Phase 1 初始版本无封面提取；已在 1.1.0-cover 中补上。阅读器、标注、知识仓库、TTS、统计、`.moye` 备份仍未实现。
- 搜索为 `LIKE`，尚未建立 FTS5。
- Windows 首次从零构建时 `package:sqlite3` 可能需要下载原生 DLL；本机已缓存。

## [0.1.0-phase0] - 2026-11-02

### Added

- Phase 0 Flutter 技术验证工程（Windows / Android）。
- PDFium 渲染、文字层识别、字符矩形、选区回读、四色高亮与 JSON 锚点。
- EPUB3 解析、TOC、封面、块级文本、元素级 CFI、字号/行距重排。
- DOCX OOXML 解析、标题/段落/列表/表格/图片/链接、段落路径定位。
- 系统 TTS Adapter：声音枚举、语速、暂停/继续、句级推进与回调日志。
- 真实样书生成器与 9 个单元测试、3 组 Windows 集成测试/探针。
- Phase 0 技术选型、插件兼容性、风险、架构、定位、测试与 Phase 1 计划文档。
- Android debug APK 与 SHA-256。

### Verified

- Windows debug 构建成功。
- Windows 集成测试通过（PDF/EPUB/DOCX/TTS）。
- Android debug APK 从 ASCII 路径构建成功。
- EPUB CFI 经 epub.js 0.3.93 解析验证。

### Known limitations

- Android 运行验证未完成：无真机，模拟器硬件虚拟化未启用，ADB server 挂起。
- 仓库中文路径会导致 Android 构建失败；当前依赖 ASCII 副本。
- EPUB 生产渲染引擎未选定；当前为最小原型。
- 数据层仍为 JSON；SQLite/备份/知识仓库/OCR 未实现。
- TTS 为句子级同步，不是单词级；后台/锁屏播放未实现。
