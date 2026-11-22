# MOYE 墨页 · Phase 0 技术预研与风险验证报告

版本：V1.0 / Phase 0
日期：2026-11-02
状态：**可执行部分完成；Android 运行验证未闭合；等待用户审核，Phase 1 未开始。**

## 1. 执行摘要

Phase 0 的目标不是做产品 UI，而是回答四个问题：

1. Flutter 能否在 Windows 与 Android 构建？
2. PDF、EPUB、DOCX 能否真实读取、定位和选择文字？
3. Windows/Android 的系统 TTS 能否支撑句子级同步朗读？
4. 哪些技术路线会阻塞 V1，必须在写业务代码前调整？

结论：

- **Windows 核心链路已真实跑通。** PDFium 文字层/字符矩形/选区、EPUB3 解析与 CFI、DOCX 结构定位、Windows 系统 TTS 都通过了真实文件与真实窗口集成测试。
- **Android APK 已构建成功**，但当前主机没有 Android 真机，模拟器硬件虚拟化未启用，ADB server 在本机挂起，因此 **Android 上的 PDF/TTS 运行验证未完成**。不能把“构建成功”写成“Android 功能通过”。
- **仓库中文路径是 Android 构建阻塞项。** 直接构建失败；复制到 ASCII 路径后才成功。`android.overridePathCheck=true` 不足以解决 NDK/CMake 阶段的问题。
- **EPUB 生产引擎仍未选定。** Phase 0 自建了解析器并验证了 CFI，但它只覆盖样例子集；V1 必须在 Phase 2 前对 Readium、epub.js WebView、增强自建引擎做正式对比。
- **数据层/备份/知识仓库/OCR 未实现，也不应在 Phase 0 实现。** 当前 JSON 仅用于验证锚点序列化，不是 V1 数据库。

## 2. Phase 0 验收矩阵

| # | 任务 | 结果 | 证据 / 说明 |
|---:|---|---|---|
| 1 | Flutter Windows 构建 | **通过** | Flutter 3.47.9 + VS 2022 C++；debug exe 构建成功 |
| 2 | Flutter Android 构建 | **有条件通过** | 仅 ASCII 路径构建成功；中文路径失败 |
| 3 | Windows PDF 阅读 | **通过** | 3 页真实 PDF，PDFium 全页加载 |
| 4 | Android PDF 阅读 | **未验证** | APK 含 PDFium，但无设备运行 |
| 5 | EPUB 解析和文字选择 | **部分通过** | 解析/重排/CFI 通过；SelectionArea 已接入，但未做自动化拖选测试 |
| 6 | DOCX 解析 | **通过** | 标题/段落/列表/表格/图片/超链接/路径 |
| 7 | PDF 文字选择和页面坐标 | **通过（程序化选区）** | 选区 70..88 回读；字符矩形真实坐标 |
| 8 | EPUB CFI 定位 | **通过（有限）** | 生成 CFI 经 epub.js 0.3.93 解析；复杂范围未验证 |
| 9 | DOCX 段落定位 | **通过** | `body/p[20]` + 偏移 7 |
| 10 | Windows 本地 TTS | **通过** | 6 个系统声音；中文声音可用；暂停/继续/完成回调 |
| 11 | Android 本地 TTS | **未验证** | APK 含插件与 TTS 查询声明；未在设备运行 |
| 12 | 文字同步高亮路线 | **句子级队列通过** | 逐句提交 + 完成回调推进；单词级未实现 |

> 判定：Phase 0 **不是全平台完成**。第 4、11 项是明确未闭合项；第 5 项的文字选择只完成结构接入，不是完整交互验收。

## 3. 实际完成的功能

### 3.1 PDF

- PDFium 渲染与缩放查看。
- 文本型/扫描型 PDF 的启发式识别。
- 文字层读取、页数、A4 页面尺寸。
- 字符偏移、字符矩形、选区回读。
- 四色高亮入口；保存到应用私有目录 JSON。
- 选区坐标绘制高亮。
- 扫描型 PDF 无文字层时仍可打开/加载；本探针未自动验证页面绘制，不要求 OCR。

### 3.2 EPUB

- EPUB3 container/OPF/spine/nav 解析。
- 标题、作者、语言、identifier、封面。
- 章节 TOC、章节纯文本、块级结构。
- 元素级 CFI 生成。
- 字号、行距、阅读主题切换。
- 章节内 SelectionArea 文字选择与段内标注入口。
- 阅读位置（章节 + block）与标注状态写入 JSON。
- 字号重排后使用 block+charOffset 保持定位。

### 3.3 DOCX

- OOXML ZIP 读取。
- 标题层级（Heading1/2 + outline level）。
- 段落、列表、表格、图片、外部超链接。
- `body/p[N]` 段落路径 + 字符偏移。
- 表格行列文本、图片字节、链接目标。
- DOCX 页面内 SelectionArea + 标注入口。
- 阅读位置/标注 JSON 草稿。

### 3.4 TTS

- Windows 系统声音真实枚举。
- 中文/英文声音选择。
- 语速调节。
- 播放、暂停、继续、停止。
- 逐句提交、完成回调自动推进。
- 当前句高亮与点击句子起读。
- 引擎回调日志，便于验证而不是“看起来在播放”。

### 3.5 定位

- 格式无关 `ReadingAnchor`。
- PDF rect/字符范围、EPUB spine/block/CFI、DOCX path/offset。
- quote + contextBefore/After + textHash。
- 重复 quote 的上下文消歧单测。
- 源文件变化时的保守重锚定策略（设计 + 重复 quote 消歧单测；未做源文件替换/孤儿锚点的端到端测试）。

## 4. 明确未完成

- Android 真机安装、PDF 渲染、PDF 选区、TTS 声音/暂停/继续。
- 100 本书导入、数百页 PDF、长 EPUB、大 DOCX 性能。
- SQLite、数据库迁移、事务、外键、索引。
- `.moye` 备份、恢复、加密、损坏/磁盘不足回滚。
- 知识仓库页面、跨书籍搜索、导出。
- PDF 全文搜索 UI、目录、双页、连续滚动模式。
- PDF 跨页/旋转页/双页标注。
- EPUB 复杂 CSS、脚注、ruby、表格、MathML、脚本内容。
- DOCX inline 加粗/斜体、合并单元格、页眉页脚、修订、`.doc`。
- Android 后台/锁屏 TTS。
- OCR。
- 正式安装包、签名、发布流程。

## 5. 技术路线结论

### 5.1 PDF：保留 `pdfrx 2.11.0`

Windows 实测可行。Android 需要运行验证。构建要求 Developer Mode/符号链接权限；UI 自定义菜单要处理 `material_ui` 类型隔离。

### 5.2 EPUB：Phase 0 原型可用，生产引擎待定

`epubx` 与 `pdfrx` 存在 `image`/`archive` 传递依赖冲突，不能同时使用。自建解析器证明了解析、重排、CFI 的可行性，但不等于 EPUB3 生产引擎。

Phase 2 前必须做一次正式对比：

1. Readium 系（若 Windows Flutter 支持成熟）。
2. epub.js + WebView 容器（需验证 Windows WebView2 与本地资源服务）。
3. 增强自建纯 Dart 引擎（可控，但 CSS/CFI 工作量大）。

### 5.3 DOCX：自建 OOXML 可作为基础

满足“阅读、搜索、选中、标注”的结构化基础；不追求 Word 编辑级复刻。Phase 2 补 inline run、复杂表格、isolate 解析与 `.doc` 转换提示。

### 5.4 TTS：`flutter_tts` + 句级队列

Windows 已实测。V1 明确句子级同步，不承诺单词级。Android 24/25 需降级暂停；后台/锁屏需要原生层。保留 `TtsAdapter`，未来可接 Kokoro 等本地模型，但不能让 UI 依赖具体引擎。

## 6. 修改/新增文件

### 原型代码

- `spikes/phase0_lab/lib/main.dart` — 应用入口、PDFium 初始化、中文 locale。
- `spikes/phase0_lab/lib/app/` — Shell、主题、总览。
- `spikes/phase0_lab/lib/core/` — 句子切分、ReadingAnchor、JSON 存储。
- `spikes/phase0_lab/lib/labs/pdf_lab.dart` — PDF 渲染、选区、坐标、高亮。
- `spikes/phase0_lab/lib/engines/epub/epub_document.dart` — EPUB3 解析、块结构、CFI。
- `spikes/phase0_lab/lib/engines/docx/` — DOCX 模型与 OOXML 解析器。
- `spikes/phase0_lab/lib/engines/tts/tts_service.dart` — TTS Adapter/句级队列。
- `spikes/phase0_lab/lib/labs/` — PDF/EPUB/DOCX/TTS 四个 Lab。
- `spikes/phase0_lab/assets/fixtures/` — 生成的真实样书与标记文本。

### 测试与工具

- `scripts/generate_fixtures.py` — 可复现 PDF/扫描 PDF/EPUB3/DOCX/TXT/MD 样书。
- `spikes/phase0_lab/test/parsers_test.dart` — 8 个解析/锚点测试；与 `widget_test.dart` 合计 9 个。
- `spikes/phase0_lab/test/widget_test.dart` — 总览 UI。
- `spikes/phase0_lab/integration_test/phase0_labs_test.dart` — 四 Lab 真实窗口集成测试。
- `spikes/phase0_lab/integration_test/pdf_engine_probe_test.dart` — PDFium 几何/扫描件探针。
- `spikes/phase0_lab/integration_test/tts_engine_probe_test.dart` — 系统 TTS 探针。
- `spikes/phase0_lab/tool/inspect_fixtures.dart` — 打印 EPUB CFI/DOCX 路径等可审计信息。

### 平台配置

- `spikes/phase0_lab/android/app/src/main/AndroidManifest.xml` — TTS_SERVICE 查询、中文标签。
- `spikes/phase0_lab/android/gradle.properties` — `android.overridePathCheck=true`（仅缓解，不解决中文路径）。
- `spikes/phase0_lab/pubspec.yaml` — 锁定 Phase 0 依赖。

### 文档与产物

- `README.md`、`.gitignore`。
- `docs/phase-0/` 本目录全部报告。
- `artifacts/phase-0/moye_phase0-debug.apk`（本地，不纳入 Git）。
- `artifacts/phase-0/SHA256SUMS.txt`。

## 7. 测试项目与结果

| 命令 | 结果 |
|---|---|
| `flutter test test` | **9 个测试全部通过**（8 parser + 1 widget） |
| `flutter test integration_test/phase0_labs_test.dart -d windows` | **通过**（PDF/EPUB/DOCX/TTS 四 Lab） |
| `flutter test integration_test/pdf_engine_probe_test.dart -d windows` | **通过** |
| `flutter test integration_test/tts_engine_probe_test.dart -d windows` | **通过** |
| `flutter build windows --debug` | **成功** |
| `flutter build apk --debug`（ASCII 路径副本） | **成功** |
| `dart analyze lib` | **无 issue** |
| `flutter analyze`（中文路径） | **工具崩溃**（analysis server code 255）；不是代码 issue |
| Android 真机安装与功能 | **未执行（环境缺口）** |

关键证据：

- PDF：3 页；文字 148 字符；标记偏移 70..88；选区回读；矩形坐标真实。
- 扫描 PDF：文字 0 字符，但页面仍可渲染。
- EPUB：2 章；CFI `epubcfi(/6/2[ch1]!/4/2/6/1:4)` 经 epub.js 0.3.93 解析，输出见 `evidence/cfi-epubjs.txt`。
- DOCX：23 块；`body/p[20]` 偏移 7；表格/图片/链接存在。
- TTS：6 个 Windows 声音；中文可用；`pause → continue → complete` 真实回调。
- Android APK：含 3 个 ABI、PDFium、TTS_SERVICE 查询；Debug 180 MB。

详细输出见 [test-report.md](test-report.md) 与 [evidence/](evidence/)。

## 8. 尚未解决的问题

1. **Android 运行验证缺失（P0）**：没有真机；模拟器硬件虚拟化未启用；ADB server 挂起。
2. **中文路径构建阻塞（P0）**：直接构建失败；ASCII 副本成功。
3. **EPUB 生产引擎未定（P1）**：自建解析器只覆盖样例子集。
4. **EPUB/DOCX 文字选择交互未自动化（P1）**：SelectionArea 已接入，但没有真实拖选/菜单的自动化证据。
5. **PDF 选区测试是程序化设置**：证明 delegate/渲染/回读链路，不等于鼠标拖拽体验验收。
6. **跨重启恢复未完整验收（P1）**：EPUB/DOCX 已写 JSON，但没有做关闭重开矩阵。
7. **标注持久化只到 JSON**：PDF 高亮保存路径/SnackBar 已跑通；未做重启后读回/绘制验收。SQLite、事务、迁移未开始。
8. **大文件/大书库性能未验证（P1）**。
9. **TTS 后台/锁屏、API 24/25 暂停降级未实现**。
10. **DOCX inline 样式、复杂表格、`.doc` 转换未实现**。

## 9. 技术风险摘要

完整清单见 [risk-register.md](risk-register.md)。最需要用户关注：

- **P0 R-01 Android 运行验证**：没有它，Phase 0 不能算跨平台完成。
- **P0 R-02 构建路径**：中文路径会让 Windows 上的 Android 构建不可复现。
- **P1 R-03/R-04 EPUB 引擎与 CFI**：原型 CFI 通过单样本验证，但不等于复杂 EPUB3 生产可用。
- **P1 R-12/R-13 数据层/备份**：数据安全尚未进入实现阶段，Phase 1/5 必须优先。
- **P1 R-07/R-08 PDF 旋转/混合页**：当前只覆盖 A4 竖版单页。

## 10. 交付物

- Phase 0 技术原型：`spikes/phase0_lab`。
- 技术选型报告、插件兼容性报告、风险清单、推荐架构、定位设计、测试报告、Phase 1 计划。
- Windows 可运行调试构建。
- Android 调试 APK + SHA-256（本地产物）。
- Git 提交（Phase 0 基线）。

## 11. 下一阶段建议

**建议不要直接把 Phase 0 标记为“全平台完成”。**

推荐顺序：

1. 用户提供一台 Android 真机（Android 11+，开启 USB 调试），安装 `artifacts/phase-0/moye_phase0-debug.apk`。
2. 完成 Android 最小运行验收：PDF 打开/缩放/文字选择、EPUB 打开/字号、DOCX 打开、TTS 声音/暂停/继续。
3. 修复 Android 运行问题后，再决定 Phase 1 是否开工。
4. 同时把仓库迁移到 ASCII 路径，或固化 ASCII 构建副本脚本。
5. Phase 2 前完成 EPUB 生产引擎对比，不能把当前自建渲染器直接当 V1。

如果用户接受“先做 Phase 1 基础设施，Android 运行验收并行补”，可以作为例外批准，但必须在 Phase 1 交付中标明 Android 未验收，不能用它做发布门禁。

## 12. 等用户确认的事项

请选择：

- **A. 先补 Android 真机验证，再开 Phase 1（推荐）**。
- **B. 接受 Windows 验证结果，Phase 1 先做基础设施，Android 验收并行补**（需明确风险）。
- **C. 调整 Phase 0/1 验收标准**（例如把 Android 运行验证移到 Phase 2 前）。

在收到确认前，不进入 Phase 1，不把 Phase 0 的 Android 项标记为通过。

