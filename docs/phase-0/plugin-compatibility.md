# Phase 0 插件兼容性报告

日期：2026-11-02

## 1. 依赖清单

| 包 | 版本 | 用途 | Windows | Android |
|---|---:|---|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7 | 框架 | 构建、运行通过 | 构建通过 |
| `pdfrx` | 2.11.0 | PDFium 渲染、文字层、选区 | 通过 | 构建通过，运行未验证 |
| `pdfrx_engine` | 0.9.0 | PDF 引擎抽象 | 通过 | 构建通过 |
| `pdfium_flutter` / `pdfium_dart` | 0.4.1 | 原生 PDFium | 通过 | 构建通过 |
| `flutter_tts` | 4.2.5 | 系统 TTS | 通过，6 声音 | 构建通过，运行未验证 |
| `archive` | 4.6.0 | EPUB/DOCX ZIP | 通过 | 通过 |
| `xml` | 7.1.0 | OOXML / OPF | 通过 | 通过 |
| `html` | 0.15.7 | XHTML DOM | 通过 | 通过 |
| `scrollable_positioned_list` | 0.3.8 | 可定位长列表 | 通过 | 通过 |
| `path_provider` | 2.1.6 | 应用私有目录 | 通过 | 通过 |
| `integration_test` | Flutter SDK | 真机/桌面集成测试 | 通过 | 未运行 |

## 2. 已确认的兼容性问题

### 2.1 `epubx 4.0.0` 与 `pdfrx 2.11.0` 不可共存

实际执行 `flutter pub get` 的错误：

```text
Because pdfrx >=2.11.0 depends on pdfrx_engine ^0.9.0 which depends on image ^4.8.0,
pdfrx >=2.11.0 requires image ^4.8.0.
And because epubx >=3.0.0 depends on image ^3.0.8,
pdfrx >=2.11.0 is incompatible with epubx >=3.0.0.
```

`epubx` 还要求 `archive ^3.1.6` 和 `xml ^6.0.1`；同时降级会牵动整个依赖图。Phase 0 没有选择降级 PDF 引擎，而是移除 `epubx`，自建最小解析器。

这个冲突本身是 Phase 0 的重要产出：V1 不能假设“常见 Flutter 包可以随意叠加”。

### 2.2 `pdfrx` Windows 构建需要符号链接

官方 README 明确：Windows native assets 构建使用 symlink，需开启 Developer Mode。本机未开启，但当前管理员 shell 有符号链接权限，构建成功。

影响：普通开发者/CI 使用非管理员 shell 时可能直接失败。Phase 1 的构建文档必须包含 Developer Mode 或管理员权限要求。

### 2.3 `pdfrx` 使用 `material_ui` 包

`pdfrx 2.11.0` 的 Material 组件来自 `material_ui 1.9.0`，不是 Flutter 自带 `material.dart`。两个包的类型不能混用。

Phase 0 的处理：

- UI 使用 Flutter Material。
- 不使用 `PdfViewerParams.customizeContextMenuItems` 等依赖 `material_ui` 类型的扩展。
- 通过 `PdfTextSelectionParams.onTextSelectionChange` + 自建底部工具栏完成标注入口。

如果 V1 需要深度定制 PDF 右键菜单，需要统一引入 `material_ui` 的主题与本地化，不能直接把两种 `ContextMenuButtonItem` 混在一起。

### 2.4 Android 中文路径

直接构建失败：

```text
Your project path contains non-ASCII characters...
Gradle task assembleDebug failed
```

添加 `android.overridePathCheck=true` 后继续构建，但在 `jni` 的 CMake 阶段失败：

```text
Execution failed for task ':jni:buildCMakeDebug[arm64-v8a]'.
Expected output file at ...\build\jni\intermediates\cxx\Debug\...\obj\arm64-v8a\libdartjni.so
```

将源码复制到 ASCII 路径后构建成功。结论：

- 不是代码错误，是 Windows 工具链对 CJK 路径的兼容问题。
- `android.overridePathCheck=true` 不足以解决。
- V1 仓库应放在 ASCII 路径，或建立稳定的 ASCII 构建副本/CI。

### 2.5 `flutter_tts` Android Kotlin 警告

构建输出：

```text
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): flutter_tts
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

当前 Flutter 3.47.9 仍能构建，但这是**未来升级阻塞项**。Phase 1 应锁定 Flutter 版本，Phase 4 前评估 `flutter_tts` 的新版本或 fork。

### 2.6 Windows TTS 的 NuGet 依赖

`flutter_tts` Windows CMake 需要 `nuget.exe`：

```text
CMake Error at flutter/ephemeral/.plugin_symlinks/flutter_tts/windows/CMakeLists.txt:12:
  nuget.exe not found. Please install it.
```

项目外安装 NuGet CLI 并加入 PATH 后构建通过。V1 构建脚本必须固定这一步。

### 2.7 Android TTS 包可见性

Android 11+ 需要声明 TTS service 查询，否则声音枚举可能为空。已在 `AndroidManifest.xml` 加入：

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE"/>
  </intent>
</queries>
```

APK manifest 已用 `aapt2 dump xmltree` 验证该 action 存在。运行仍待 Android 设备验证。

## 3. 构建结果

### Windows

```text
flutter build windows --debug
√ Built build\windows\x64\runner\Debug\moye_phase0.exe
```

Windows 集成测试（真实窗口）均通过：

- PDF 文字层、选区回读、保存高亮
- EPUB 元数据/CFI/排版
- DOCX 定位
- TTS 声音、播放、暂停、停止

### Android

ASCII 构建副本：

```text
flutter build apk --debug
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

APK 静态结果：

- 包名：`app.moye.moye_phase0`
- minSdk 24，target/compileSdk 36
- 标签：`墨页 Phase 0`
- ABI：`armeabi-v7a`、`arm64-v8a`、`x86_64`
- 包含 `libpdfium.so`、`libpdfrx_pdfium_gate.so`、`libdartjni.so`
- 含 TTS_SERVICE 查询
- Debug 通用包 180 MB（非发布体积）

## 4. 未验证项

- Android 上的 PDFium 实际渲染与文字选择。
- Android 上的系统 TTS 声音枚举、中文语音、暂停/继续。
- Android 后台/锁屏播放（Phase 4 才实现）。
- iOS/macOS/Linux（明确不在 V1 范围）。

## 5. 建议

1. Phase 1 开始前把仓库迁到 ASCII 路径，或把“ASCII 构建副本”写进脚本并在 CI 复现。
2. 锁定 Flutter 3.47.9；在升级前检查 `flutter_tts` 的 Built-in Kotlin 兼容性。
3. 为 Windows 构建准备 NuGet、Developer Mode 和 Visual Studio C++ 工作负载检查脚本。
4. Android 运行验证必须用真机完成，尤其是 TTS 声音包和 PDFium ABI。
5. PDF 自定义菜单若必须深度定制，再统一引入 `material_ui`；否则保持当前自建工具栏，降低类型冲突。
