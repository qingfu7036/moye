# Phase 0 测试报告

日期：2026-11-02
测试对象：`spikes/phase0_lab` 技术原型；不是 V1 验收。

## 1. 测试范围

| 层次 | 内容 | 状态 |
|---|---|---|
| 单元测试 | 句子切分、锚点 JSON、上下文重锚定、EPUB 解析、DOCX 解析、概览 UI | 通过 9 项 |
| 桌面集成测试 | 四个 Lab 启动、PDF 探针/选区/高亮、EPUB CFI/字号、DOCX 定位、TTS 控制 | 通过 |
| 引擎探针 | PDFium 文本几何、扫描 PDF；系统 TTS 声音与回调 | 通过 |
| Android | APK 构建 + 包结构静态检查 | 构建通过 |
| Android 运行 | PDF/EPUB/DOCX/TTS 真机执行 | **未完成** |

## 2. 单元测试

`flutter test test`：

```text
00:00 +9: All tests passed!
```

覆盖：

- 中英混排句子切分、偏移保持、长句上限。
- PDF 锚点 JSON 往返；EPUB/DOCX 锚点尚未单独做 JSON 往返测试。
- 重复 quote 的 context 消歧。
- EPUB3 元数据、spine、TOC、封面、纯文本、CFI 精确值。
- DOCX 标题/列表/表格/图片/链接/段落路径/偏移。
- 总览页渲染。

## 3. Windows 集成测试

`flutter test integration_test/phase0_labs_test.dart -d windows`：

```text
PdfDocument initial load: ... sample.pdf (646 ms)
PdfViewer: Loaded 3 of 3 pages in 1 ms
00:15 +1: (tearDownAll)
00:15 +1: All tests passed!
```

覆盖真实窗口内的：

- PDF：文本型标签、页数、探针、`setTextSelectionPointRange` 回读、选区工具条、黄色高亮写入、SnackBar。
- EPUB：真实样书渲染、标题、CFI 标签、字号增加后内容仍可读。
- DOCX：标题、结构摘要、定位按钮、`docx-probe-result` 的 `body/p[...]`。
- TTS：系统声音数量非零、句子列表、播放、暂停、停止。

测试中的 PDF 选区是通过 Viewer 的 `PdfTextSelectionDelegate` 程序化设置选区，再由同一 delegate 回读；**不是模拟鼠标拖拽**。它证明了选区渲染/回读/几何链路，人工拖拽仍应由真实用户测试。

## 4. PDFium 探针

`flutter test integration_test/pdf_engine_probe_test.dart -d windows`：

```text
PDF_PAGES=3
PDF_PAGE_SIZE=595.2755737304688x841.8897705078125
PDF_TEXT_CHARS=148  # 第 2 页
PDF_MARKER_START=70
PDF_SELECTION=70..88
PDF_SELECTION_TEXT=MOYE-PHASE0-ANCHOR
PDF_FRAGMENT_RECTS=1
PDF_RECT=PdfRect(left: 244.4199981689453, top: 641.8257446289062,
                right: 351.62799072265625, bottom: 630.59375)
SCANNED_TEXT_CHARS=0
```

结论：

- 文本型 PDF 的文字层和字符矩形真实可得。
- 扫描型样书文字层为 0；仍可打开/加载，但本探针没有绘制/截图断言，不能声称已自动验证扫描页渲染。

## 5. 系统 TTS 探针

`flutter test integration_test/tts_engine_probe_test.dart -d windows`：

```text
TTS_INITIALIZED=true
TTS_ERROR=null
TTS_VOICES=6
Microsoft David|en-US|male
Microsoft Mark|en-US|male
Microsoft Zira|en-US|female
Microsoft Huihui|zh-CN|female
Microsoft Kangkang|zh-CN|male
Microsoft Yaoyao|zh-CN|female
...
speak #1 → start → pause → continue → complete #1
speak #2 → start → complete #2
speak #3 → start → complete #3
```

结论：

- 声音列表来自系统真实枚举，不伪造。
- 中文声音可用。
- 暂停后状态保持，继续后完成回调正常。
- 自动推进到下一句。
- TTS 队列的句子级推进成立；尚未与阅读器实际渲染句做像素/位置同步断言。单词级同步未实现。

## 6. EPUB CFI 独立验证

生成：

```text
epubcfi(/6/2[ch1]!/4/2/6/1:4)
```

用 epub.js 0.3.93 `EpubCFI` 解析（输出已保存到 `evidence/cfi-epubjs.txt`）：

```text
CFI_VALID=true
toString=epubcfi(/6/2[ch1]!/4/2/6/1:4)
spinePos=0
path={"steps":[{"type":"element","index":1},{"type":"element","index":0},
{"type":"element","index":2},{"type":"text","index":0}],
"terminal":{"offset":4}}
```

说明：

- CFI 语法和 spine/path 解析通过。
- 该验证只覆盖该样例的结构；复杂 EPUB 的 range/text assertion 未验证。
- 过程中发现并修复了一个真实错误：最初生成 `epubcfi(...)/2/6`（括号位置错误），单元测试只做了 `startsWith` 未发现；改用精确断言并独立解析后确认。

## 7. Android 构建

从 ASCII 路径构建：

```text
flutter build apk --debug
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

静态检查：

- `package=app.moye.moye_phase0`，minSdk 24，target 36。
- ABI：armeabi-v7a / arm64-v8a / x86_64。
- 含 `libpdfium.so`、`libpdfrx_pdfium_gate.so`、`libdartjni.so`。
- manifest 含 `android.intent.action.TTS_SERVICE` 查询。
- Debug 包 188,673,994 bytes；SHA-256、ABI、`libpdfium.so` 与 TTS 查询的原始输出见 `evidence/android-apk.txt`。

未执行：

- 安装到 Android 设备。
- 真机 PDF 渲染/选区。
- 真机 TTS 声音/暂停/继续。

## 8. 测试环境限制

- Android 无真机；模拟器未安装；Hypervisor 未启用；ADB server 本机挂起。
- `flutter analyze` 在中文路径下 analysis server 以 code 255 崩溃；`dart analyze lib test integration_test tool` 返回 “No issues found”。输出见 `evidence/dart-analyze.txt` 与 `evidence/flutter-analyze-crash.txt`。这与 R-02 的中文路径工具链问题一致。
- 不是“测试通过但没写”，而是“测试无法启动”。
- 因此 Phase 0 的 Android 运行验收项保持 **未完成**。

## 9. 人工测试建议（必须补）

1. Windows 鼠标拖拽选区、不同缩放、双页/连续滚动。
2. Windows 100%/125%/150% DPI。
3. Android 真机：长按选区、系统选择菜单、TTS 声音包缺失、API 26 以下暂停降级。
4. 导入 10 本真实 EPUB/DOCX/PDF，检查不是只对生成样书有效。
5. 关闭应用再打开，确认 EPUB/DOCX 的字体/位置/标注恢复。
6. 替换同名书籍，确认标注重锚定或 orphaned 提示。

## 10. 证据索引

`evidence/` 保存了单元测试、集成测试、PDF/TTS 探针、CFI epub.js 校验、Android APK 静态检查、dart analyze 与环境输出。cfi-epubjs 是一次性 Node 校验（epubjs 0.3.93）；仓库保留输出，校验脚本未纳入 Phase 0。

## 11. 测试结论

Windows：**Phase 0 核心可执行链路已跑通；UI 交互与重启恢复仍需人工/后续测试**。
Android：**构建通过，运行验证缺失**。
在 Android 运行验证完成前，不把 Phase 0 判定为全平台完成。

