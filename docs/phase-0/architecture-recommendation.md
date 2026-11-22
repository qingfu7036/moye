# Phase 0 推荐架构

日期：2026-11-02
适用范围：Phase 1 起步架构；不是最终实现。

## 1. 分层

```text
lib/
├── app/                    # MaterialApp、主题、路由、响应式 Shell
├── core/
│   ├── database/           # SQLite、迁移、DAO（Phase 1）
│   ├── storage/            # 应用私有目录、书籍/封面/附件仓库
│   ├── backup/             # .moye manifest、校验、原子恢复（Phase 5）
│   ├── search/             # 书库/知识库搜索
│   ├── platform/           # 文件选择、路径、设备能力
│   ├── locator.dart        # ReadingAnchor、重锚定
│   └── sentence.dart       # 句级切分（TTS 共用）
├── features/
│   ├── library/            # 书库、书架、标签、导入
│   ├── reader/             # 阅读 Shell、目录、进度、书签
│   ├── annotations/        # 选区工具条、高亮、批注
│   ├── knowledge/          # 摘录、笔记、标签、导出
│   ├── speech/             # 朗读 UI、播放状态
│   ├── statistics/         # 阅读会话、日历
│   └── settings/
├── engines/
│   ├── reader_engine.dart  # 格式无关接口
│   ├── pdf/
│   ├── epub/
│   ├── docx/
│   └── tts/
└── main.dart
```

Phase 0 的 `spikes/phase0_lab` 只用于验证，不作为 V1 的 `lib/` 直接复制。把 Lab 的页面状态、样式和测试数据带入 V1 会制造技术债。

## 2. 阅读引擎接口

> 这是待验证的 V1 目标接口，**Phase 0 没有实现 `ReaderEngine` 或 `TtsAdapter` 抽象**；Phase 0 只有各格式 Lab 和具体 `TtsService`。Phase 2 出现第二个真实引擎时再抽接口，避免先造空壳。

V1 目标：让 `ReaderPage` 只依赖接口，而不是 `PdfViewer`、`EpubView` 或 DOCX 专用组件。

```dart
abstract interface class ReaderEngine {
  Future<ReaderDocument> openDocument(BookSource source);
  Future<void> closeDocument();
  Future<DocumentMetadata> getDocumentMetadata();
  Future<List<TocNode>> getTableOfContents();
  Future<ReadingAnchor?> getCurrentPosition();
  Future<void> restorePosition(ReadingAnchor anchor);
  Future<String> getTextForRange(ReadingAnchor anchor);
  Future<List<SearchHit>> searchText(String query);
  Future<void> jumpToLocation(ReadingAnchor anchor);
}
```

平台/格式扩展点：

- `PdfEngine`：pdfrx；负责页文本、字符矩形、旋转、扫描页标记。
- `EpubEngine`：Phase 2 决定 Readium / epub.js / 自建；负责 CFI、章节、重排。
- `DocxEngine`：自建 OOXML；负责 `body/p[N]`、表格、图片、inline 样式。
- `TxtMarkdownEngine`：字符偏移。
- `TtsAdapter`：系统 TTS、声音、语速、暂停、完成回调；不暴露 `FlutterTts` 类型给 UI。

约束：

1. 引擎不能 import `features/reader`。
2. 引擎不能直接读写 SQLite；由 Repository 注入文档和保存回调。
3. UI 不能持久化“页码”或“百分比”作为唯一位置。
4. 任何格式的“选中文字”必须同时返回位置锚点。

## 3. 位置与标注数据流

```text
用户选择文字
  → 引擎返回 quote + 结构定位 + 格式坐标
  → AnnotationService 补充 contextBefore/contextAfter + textHash
  → Repository 事务写 annotations + (可选) reading_progress
  → 标注列表/知识库读取同一 anchor
  → 点击标注：引擎 restorePosition(anchor) + 高亮
```

`ReadingAnchor` 是格式无关的持久化模型；PDF rect、EPUB CFI、DOCX path 都是附加字段，不替代 quote/context。

源文件被替换时：

1. 比对文件内容哈希。
2. 哈希一致 → 直接恢复。
3. 哈希不同 → 用 quote + context 重锚定；低置信度不静默跳转，提示用户。
4. 无法恢复 → 保留标注并标记 `orphaned`，允许导出/删除，不丢用户笔记。

详细字段见 [locator-design.md](locator-design.md)。

## 4. 数据层

Phase 1 推荐 **SQLite + 手写迁移**（`sqlite3` + DAO）或 **drift**。选择标准：

- 支持 Windows/Android 同一套 schema。
- 支持事务、外键、索引、迁移。
- 不依赖云端或代码生成导致构建不稳定。

最低表：

```text
books(id, title, author, format, file_path, file_hash, cover_path, status,
      created_at, updated_at, last_opened_at)
shelves(id, name, sort_order)
book_shelves(book_id, shelf_id)
tags(id, name, color)
book_tags(book_id, tag_id)
reading_progress(book_id, anchor_json, percent, mode, updated_at)
annotations(id, book_id, type, color, quote, anchor_json, note,
            created_at, updated_at, orphaned)
bookmarks(id, book_id, anchor_json, label, created_at)
notes(id, book_id, annotation_id, title, body, created_at, updated_at)
reading_sessions(id, book_id, started_at, ended_at, active_ms, pages_delta)
speech_progress(book_id, anchor_json, voice_id, rate, updated_at)
settings(key, value_json)
attachments(id, book_id, relative_path, mime, size, hash)
```

关键约束：

- 书籍文件复制到应用私有 `books/`；数据库只存相对路径。
- 删除书籍需要明确选择“只删书 / 连标注一起删”，默认不静默级联删除知识数据。
- 所有多表写入使用事务。
- `schema_version` + 迁移测试，禁止启动失败后继续写入。

## 5. 文件与缓存

```text
<app-support>/
├── database/library.db
├── books/
├── covers/
├── attachments/
├── cache/          # 可清理
├── speech/         # 可选缓存
├── backups/
└── logs/
```

缓冲区清理必须只触碰 `cache/`，且通过“路径白名单 + 当前打开书籍保护”双重检查。

## 6. TTS 架构

```text
ReaderEngine → TtsTextExtractor → SentenceSegmenter
    → TtsQueue (逐句)
    → TtsAdapter (系统 TTS)
    → SentenceHighlightController → 阅读器
```

Phase 0 已验证 Windows 的逐句完成回调。V1 需要补：

- Android API 24/25 的暂停降级。
- 后台播放/锁屏控制（Android 前台服务 + MediaSession；Windows 音频会话）。
- 声音变更、语言包缺失、TTS 引擎不可用的 UI 反馈。
- 阅读位置与听书位置独立保存，支持互跳。

## 7. 备份（Phase 5，不是 Phase 0 实现）

`.moye` 必须包含 manifest、数据库、书籍、封面、附件、标注/笔记/进度/设置。恢复流程：

```text
选择包 → 读取 manifest → 版本/空间检查 → 临时目录解压
→ 逐文件哈希校验 → 数据库完整性/迁移检查
→ 原子替换 → 失败回滚 → 清理临时目录
```

恢复失败不得破坏现有数据库；覆盖式恢复必须明确提醒用户。详细格式在 Phase 5 单独定稿。

## 8. Phase 1 最小可交付

1. 新建 V1 `lib/` 架构，不直接复制 Lab 页面。
2. SQLite schema v1 + 迁移测试。
3. 导入 1 个 TXT/Markdown/PDF/DOCX/EPUB，复制到 `books/`，计算哈希。
4. 书库网格/列表、删除确认、重新打开。
5. Windows/Android 启动，关闭重启后数据仍在。
6. 建立 CI/脚本：analyze、unit test、Windows build、ASCII 路径 Android build。

不在 Phase 1 做完整阅读器；阅读器在 Phase 2 通过 `ReaderEngine` 接入。

## 9. 架构红线

- 禁止把 PDF/EPUB/DOCX 逻辑写进一个 `ReaderPage`。
- 禁止把绝对路径写入数据库或备份。
- 禁止用“页码”作为唯一阅读位置。
- 禁止只保存选中字符串而不保存定位与上下文。
- 禁止用 JSON 替代 V1 数据库。
- 禁止在没有 Android 运行验证的情况下宣称跨平台功能完成。
