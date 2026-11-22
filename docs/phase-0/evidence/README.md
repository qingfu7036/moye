# Phase 0 证据索引

本目录保存可审计的原始输出，均来自 2026-11-02 的本地 Windows 构建/测试环境。

| 文件 | 内容 | 说明 |
|---|---|---|
| `unit-tests.txt` | `flutter test test` | 9 个测试通过 |
| `integration-windows.txt` | 四 Lab Windows 集成测试 | PDF 选区/高亮、EPUB 字号、DOCX 定位、TTS |
| `pdf-engine.txt` | PDFium 几何探针 | 文本 148 字符、标记 70..88、矩形、扫描件 0 字符 |
| `tts-engine.txt` | 系统 TTS 探针 | 6 个声音、暂停/继续/完成回调 |
| `cfi-epubjs.txt` | epub.js 0.3.93 CFI 解析 | `CFI_VALID=true`，spinePos/path |
| `fixture-inspection.txt` | 样书解析结果 | EPUB CFI、DOCX path/offset、表格/链接 |
| `android-build.txt` | Android 构建输出 | ASCII 副本上的 `assembleDebug` |
| `android-apk.txt` | APK 静态检查 | SHA-256、badging、ABI、native libs、TTS query |
| `dart-analyze.txt` | `dart analyze lib test integration_test tool` | No issues found |
| `flutter-analyze-crash.txt` | `flutter analyze` | 中文路径下 analysis server code 255 |
| `environment.txt` | 主机/Flutter/Android/Java 环境 | 工具链版本 |

## 未保存/未验证

- Android 真机安装、PDF 渲染/选区、TTS 声音与暂停：未执行。
- `cfi-epubjs.txt` 是使用 `cache/research/epubjs-node` 中的 epubjs 0.3.93 做的一次性校验；校验脚本未纳入仓库。
- 测试日志包含中文路径的终端编码乱码；这是 Windows 控制台编码，不是测试结果编码。
