# Phase 0 技术选型报告

日期：2026-11-02
结论前提：只覆盖 V1 所需的 Windows 10/11 + Android，不引入云端依赖。

## 1. 总体路线

```text
Flutter 3.47.9 / Dart 3.13.7
│
├── 应用层：Riverpod（Phase 1 引入）+ go_router（Phase 1）
├── 阅读引擎接口：ReaderEngine
│   ├── PdfEngine       pdfrx 2.11.0 / PDFium
│   ├── EpubEngine      Phase 0 自建解析器 → Phase 2 决定生产引擎
│   └── DocxEngine      Phase 0 自建 OOXML 解析器
├── 定位层：ReadingAnchor（格式无关）+ 各格式 Locator
├── 语音层：TtsAdapter → flutter_tts 4.2.5（Windows SAPI/UWP、Android TextToSpeech）
└── 数据层：Phase 1 起用 SQLite（drift/sqlite3）+ 文件仓库；Phase 0 仅 JSON 验证锚点
```

Phase 0 **没有**把任何阅读逻辑写进一个 `ReaderPage`。四个验证模块通过独立引擎类和独立 Lab 页面隔离。

## 2. PDF

### 选择：`pdfrx 2.11.0`

采用理由：

- Windows、Android 都使用 PDFium，渲染行为一致。
- 直接提供 `PdfViewer`、文本选择、文字层、字符矩形、页面坐标和搜索 API。
- 公开 API 能取得 `PdfPageText`、`PdfPageTextRange`、`PdfRect`，满足高亮和 TTS 句子映射。
- 支持文本型/扫描型区分所需的文字层读取；扫描件仍能正常渲染。
- 许可证宽松，无商业授权门槛。

实测（Windows）：

- `sample.pdf`：3 页，A4 595.28 × 841.89 pt。
- 第 2 页文字层 148 字符；`MOYE-PHASE0-ANCHOR` 位于偏移 70..88。
- 选区通过 `PdfViewer` 的 delegate 写回后，回读文本和范围正确。
- 文字矩形：`PdfRect(left 244.42, top 641.83, right 351.63, bottom 630.59)`。
- `scanned.pdf`：文字层 0 字符，渲染仍可用，符合无 OCR 分支。

### 已知限制

- Windows 构建使用 native assets + 符号链接，官方要求 Developer Mode；本机靠管理员权限绕过。
- `pdfrx 2.11.0` 的 Material 组件来自 `material_ui` 包，与 Flutter 自带 Material 类型并存；Phase 0 未使用它的自定义菜单类型，避免混用。
- 跨页选择可以返回多个 `PdfPageTextRange`，但 Phase 0 原型只保存单页标注。
- 旋转页、双页、混合文本/扫描页、加密 PDF 尚未覆盖。
- 全量文本搜索使用 `PdfTextSearcher` / `allMatches` 可行，但 Phase 0 只验证了读取和选区，没有完成搜索 UI。
- 中文/日文断词依赖 PDFium 的文字层；扫描件需要 OCR（V1.1 可选）。

### 备选方案与放弃原因

| 方案 | 放弃原因 |
|---|---|
| `pdfx` | 渲染可用，但没有足够的文本选择/字符矩形 API；无法满足标注定位 |
| Syncfusion PDF Viewer | 商业授权与体积风险；核心定位仍受其 API 限制 |
| 自行 FFI 绑定 PDFium | 工作量过大，Phase 0 无法在多平台稳定验证；pdfrx 已封装相同底层 |
| 原生 Windows/Android 两套阅读器 | 违反引擎隔离与维护成本目标 |

## 3. EPUB

### Phase 0 实际路线：自建 EPUB3 解析器

`epubx` 与 `pdfrx` 在当前版本存在不可调和的传递依赖冲突：

- `epubx 4.0.0` 依赖 `archive ^3.1.6`、`image ^3.0.8`、`xml ^6.0.1`。
- `pdfrx 2.11.0` 依赖 `pdfrx_engine 0.9.0`，要求 `image ^4.8.0`。
- 同时加入时 `pub get` 直接失败。

因此 Phase 0 使用 `archive + html + xml` 自建最小解析器，避免为 EPUB 降级 PDF 引擎。

实测：

- 元数据：`墨页 EPUB3 验证样本` / `MOYE Phase 0` / `zh-CN`。
- 2 个 spine 章节、2 个 TOC 条目、封面 12,715 bytes。
- 章节纯文本、标题层级、列表和段落可提取。
- CFI 示例：`epubcfi(/6/2[ch1]!/4/2/6/1:4)`。
- 该 CFI 已用 **epub.js 0.3.93 的 `EpubCFI` 解析器**独立验证：可解析，`spinePos=0`，路径终点为文本偏移 4。

### 为什么不直接把自建解析器定为 V1 生产引擎

Phase 0 解析器只覆盖验证所需子集：

- 不执行 EPUB CSS，不保留完整 inline 样式、ruby、脚注、MathML、脚本内容。
- 表格、嵌套列表、SVG、远程资源、加密字体未覆盖。
- CFI 只做元素级路径和简单文本偏移；跨节点范围、文本断言、重排后的精确恢复未完成。
- 自建渲染器目前按块渲染，不保证 EPUB3 阅读系统语义。

### Phase 2 推荐决策

优先级从高到低：

1. **Readium 系引擎（若届时 Windows Flutter 支持成熟）**：CFI、EPUB3、注释和阅读顺序最完整；需单独验证 Windows 桌面支持。
2. **epub.js + 双平台 WebView 容器**：epub.js 的 CFI/注释/重排成熟，但 Windows 需要可用 WebView2 容器，且本地资源服务、选择桥接、安全隔离都要自建。Phase 0 没有把这条路线跑通，不能直接承诺。
3. **增强当前自建引擎**：可控、纯 Dart、与标注模型统一，但要补 CSS/EPUB3/CFI 的工作量最大，适合作为长期自有引擎而不是 Phase 2 的捷径。

Phase 0 的结论是：**解析和 CFI 概念已验证，但生产 EPUB 引擎尚未选定。** 这必须在 Phase 2 前完成一次专门的渲染对比验证，不能把原型当成品。

## 4. DOCX

### 选择：自建 OOXML 解析器

没有采用 `docx_viewer` 等黑盒包，原因是无法确认其 Windows 支持、定位锚点和长期维护。自建解析器直接读取：

- `word/document.xml`：段落、标题样式、列表、表格、图片、超链接。
- `word/styles.xml`：`pStyle` → 样式名 / outline level。
- `word/_rels/document.xml.rels`：图片与外部超链接。
- `docProps/core.xml`：标题、作者。

实测样书：23 个内容块，包含 6 个一级标题、1 个二级标题、4 个列表项、1 个表格、1 张图片、1 个外部链接。定位标记解析为：

```text
路径: body/p[20]
偏移: 7
文本: 唯一段落标记：MOYE-DOCX-PARAGRAPH-ANCHOR。
链接: Flutter 官方网站 => https://flutter.dev
表格: 项目/状态/说明 ; PDF/通过/PDFium 文字选择 ; EPUB/验证中/CFI 与重排
```

### 限制

- 不渲染完整 Word 排版：分页、页眉页脚、文本框、批注、修订、合并单元格、复杂编号没有完整支持。
- 加粗/斜体等 inline run 样式在 Phase 0 模型中未保留，只保留纯文本。
- `.doc` 不支持；V1 需要转换方案（LibreOffice headless 或明确提示用户另存为 DOCX）。
- 大文档解析目前在主 isolate；Phase 2 必须把解析移入 isolate 并设置大小/超时限制。
- 段落路径基于 body 直接子节点序号，源文件被替换后需要结合 quote/context/textHash 重锚定。

## 5. 本地 TTS

### 选择：`flutter_tts 4.2.5`

- Windows：UWP `SpeechSynthesizer` + `MediaPlayer`。
- Android：系统 `TextToSpeech`。
- 支持声音枚举、语速、暂停/继续、完成/错误回调。
- 不依赖云端。

Windows 实测：

```text
TTS_INITIALIZED=true
TTS_ERROR=null
TTS_VOICES=6
Microsoft David  en-US male
Microsoft Mark   en-US male
Microsoft Zira   en-US female
Microsoft Huihui zh-CN female
Microsoft Kangkang zh-CN male
Microsoft Yaoyao zh-CN female
```

暂停/继续实测回调顺序：

```text
speak #1 → start → pause → continue → complete #1
speak #2 → start → complete #2
speak #3 → start → complete #3
```

### 同步策略

V1 Phase 0 采用 **逐句提交 + 完成回调推进**：

- 句级切分器保留原文 UTF-16 偏移。
- 每句作为独立 utterance 提交。
- 完成回调推进到下一句并更新高亮。
- 不伪造单词级时间戳，不依赖 Windows 不提供的 word-boundary 事件。

这是可靠的句子级方案，不是单词级同步。单词级同步如后续需要，应对 Android 使用 `onRangeStart`，对 Windows 评估 SAPI 事件或本地模型时间戳；不能假设 `flutter_tts` 在两平台提供相同粒度。

### 平台差异与风险

- Android `pause()` 依赖 API 26+ 的 `onRangeStart` workaround；当前 Flutter 模板构建出的 APK `minSdk=24`（aapt 实测），但 `build.gradle.kts` 使用 `flutter.minSdkVersion`；升级 Flutter 后必须复核。若仍支持 24/25，Adapter 需降级为“停止并从句首重播”。
- Windows 的语速映射是 `newRate + 0.5`；UI 以 0.5 为正常速度，避免平台语义错位。
- 系统声音数量、音色、语言包取决于用户机器；不能硬编码声音列表。
- 后台播放/锁屏控制不是 `flutter_tts` 的能力，Phase 4 需要 Android 前台服务/MediaSession 与 Windows 音频会话，不能仅靠插件。

## 6. 状态管理与路由

Phase 0 使用 `StatefulWidget` + 局部状态，目的是减少验证噪声。**不建议直接延续到 V1。**

Phase 1 推荐：

- Riverpod：书库、阅读位置、标注、TTS 状态分成独立 provider；TTS 用 `Notifier`，避免页面重建导致播放状态丢失。
- go_router：Windows 三栏和 Android 五 Tab 共用路由；阅读器路由带 bookId。
- 阅读引擎不依赖 Provider，只接收 `ReaderDocument` 和 `ReadingAnchor`，便于单测和替换。

## 7. 数据层（Phase 0 只给方向）

Phase 0 只使用 `phase0_store.dart` 写 JSON，证明锚点可序列化。**不是数据库设计。**

Phase 1 必须：

- SQLite（`drift` 或 `sqlite3` + 手写 DAO）带版本迁移。
- books / annotations / reading_progress / speech_progress 等表。
- 事务写入标注 + 进度。
- 原始书籍文件按内容哈希存入应用私有目录，数据库只存相对路径和哈希。
- 备份验证先校验 manifest 和哈希，再原子替换，失败回滚。

具体表结构在 Phase 1 的 `docs/database.md` 中定稿，不在 Phase 0 提前写死。

## 8. 结论

- PDF：`pdfrx` 可作为 V1 的 PDF 引擎候选，Windows 已实测；Android 需运行验证。
- EPUB：解析与 CFI 已验证，但生产渲染引擎未定，Phase 2 必须重新做引擎对比。
- DOCX：自建解析器满足 V1 的结构化阅读基础，但必须补 inline 样式、复杂表格、`.doc` 转换和 isolate。
- TTS：`flutter_tts` + 句级队列在 Windows 已验证；Android 需真机/模拟器验证，后台播放需原生层。
- 任何“构建通过”都不等于“平台功能通过”，尤其 Android。
