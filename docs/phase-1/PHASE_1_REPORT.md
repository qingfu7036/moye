# Phase 1 验收报告：项目基础设施与个人书库

日期：2026-11-03
版本：1.1.0+2
阶段：Phase 1（项目基础设施）

> 后续在 1.1.0 增加真实封面、1.2.0 增加 PDF 阅读器；本报告保留 Phase 1 当时验收口径，最新进度见 [Phase 2 进度](../phase-2/PHASE_2_PROGRESS.md)。
结论：**Windows 端通过本阶段可执行验收；Android APK 构建通过，运行验收未完成。阶段整体等待用户真机验收后再确认关闭。**

## 1. 本阶段交付范围

Phase 1 目标是建立可持续开发的工程底座，而不是提前做阅读器。已交付：

- Flutter 应用骨架，Windows / Android 双平台工程可构建。
- Riverpod 依赖注入、go_router 模块化路由、Material 3 明暗主题。
- SQLite 数据库、版本化迁移、外键与事务。
- 应用私有目录布局；数据库只存相对路径，支持未来跨设备迁移。
- 真实文件导入：PDF / EPUB / DOCX / DOC / TXT / Markdown。
- 文件复制、边复制边计算 SHA-256、重复检测与缺失文件修复、EPUB/DOCX 容器元数据、书籍记录与阅读进度初始化。PDF 及其他格式暂以文件名作为标题。
- 真实封面：PDF 第一页、EPUB 封面图、DOCX 首个内嵌图片，统一缓存为 JPEG；旧书异步补齐。
- 书库页面：空状态、列表/网格、搜索、状态筛选、排序、导入进度、删除确认。
- 书籍详情：格式、大小、状态、导入时间；可修改阅读状态；可删除。
- Windows 真实 UI 集成测试：导入真实 PDF → 书库出现 → 同一进程内关闭并重开数据库、重建 Widget 后仍存在 → 删除并确认私有文件消失。
- Phase 1 的单元、Widget、集成测试与文档。

明确不在 Phase 1：阅读器、标注、知识仓库、TTS、统计、`.moye` 备份。它们分别在 Phase 2–5 实现。

## 2. 代码结构

```text
lib/
├── main.dart
├── app/
│   ├── moye_app.dart          # MaterialApp.router + 主题 + 本地化
│   ├── app_router.dart        # go_router：书库 / 设置 / 占位页
│   ├── app_shell.dart         # NavigationRail（宽屏）/ NavigationBar（手机）
│   ├── providers.dart         # Riverpod 服务与书库状态
│   └── theme.dart             # 阅读器友好的墨色主题
├── core/
│   ├── app_services.dart      # 启动顺序：路径 → 数据库 → 仓库
│   ├── database/
│   │   ├── library_database.dart
│   │   └── migrations.dart    # schema v1，只追加不修改
│   ├── metadata/
│   │   └── book_metadata_extractor.dart
│   ├── models/book.dart
│   └── storage/
│       ├── app_paths.dart     # 私有目录 + 相对路径安全检查
│       └── book_file_store.dart
└── features/
    ├── library/
    │   ├── data/
    │   │   ├── book_picker.dart
    │   │   └── library_repository.dart
    │   └── presentation/
    │       ├── library_page.dart
    │       └── widgets/
    │           ├── library_toolbar.dart
    │           ├── library_results.dart
    │           ├── book_card.dart
    │           └── book_details_panel.dart
    └── settings/presentation/settings_page.dart
```

## 3. 验收矩阵

| 任务书 Phase 1 条目 | 状态 | 证据 / 说明 |
|---|---|---|
| 建立 Flutter 项目 | 通过 | 根工程 Windows + Android；`flutter --version` 与构建日志 |
| 配置 Windows | 通过 | `flutter build windows --debug`；真实窗口可启动 |
| 配置 Android | 构建通过，运行未验证 | `app-debug.apk` 构建成功；本机无真机，模拟器硬件虚拟化不可用 |
| 建立数据库 | 通过 | schema v1、外键、WAL、迁移事务；20 个数据库/仓库测试 |
| 建立本地存储服务 | 通过 | 私有目录布局；相对路径越界拒绝；删除隔离区 |
| 建立文件导入系统 | Windows 通过 | 真实 PDF 经真实 UI 导入；EPUB/DOCX 元数据单测；Android 仅构建 |
| 建立书库页面 | 通过 | 空状态、网格/列表、搜索、筛选、排序、导入、详情、删除 |
| 建立基础主题系统 | 通过 | Material 3、明暗主题、中文本地化、手机/桌面导航 |
| 建立模块化架构 | 通过 | `core` / `features` / `app` 分层；仓库不依赖 UI |

## 4. 实际执行的验证

### 4.1 静态检查

```text
dart analyze lib test integration_test
Analyzing lib, test, integration_test...
No issues found!
```

说明：`flutter analyze` 在仓库中文路径下仍会让 analysis server 以 code 255 崩溃，这是 Phase 0 已记录的 R-02 工具链问题，不是代码 issue；使用 `dart analyze` 得到上述结果。

### 4.2 单元与 Widget 测试

```text
flutter test
00:09 +26: All tests passed!
```

覆盖：

- schema v1 建表、外键与 `journal_mode=wal` 断言；
- 真实 PDF 导入、复制、哈希、阅读进度初始化；
- PDF 第一页 / EPUB OPF 封面 / DOCX 首个内嵌图片提取到 `covers/`；
- EPUB / DOCX 元数据读取，PDF 回退文件名；
- 重复内容拒绝并清理重复副本；
- 缺失原文件的重复导入修复；
- 不支持的扩展名不写文件；不支持的流在创建缓存文件前被拒绝；读取中断时清理缓存；
- 关闭数据库后重新打开仍能读到书籍；
- 状态筛选与 `LIKE` 通配符/转义搜索（`%`、`_`、`!`）；
- 删除书籍、进度和私有文件；
- 相对路径 `..` 越界拒绝；
- 数据库版本高于应用支持版本时拒绝打开；
- 隔离后崩溃的启动恢复；
- 空书库渲染、设置路由可达；
- 390×844 空书库工具栏不溢出（有书网格/详情/大字体未覆盖）；
- 导入后的卡片、详情、删除流程（Widget 层）；
- 重复导入不会产生第二张卡片。

### 4.3 Windows 真实 UI 集成测试

```text
flutter test integration_test/phase1_library_test.dart -d windows
00:03 +1: All tests passed!
```

测试使用真实 PDF 文件与真实 SQLite，但根目录是 `Directory.systemTemp.createTemp()` 创建的临时目录；测试同时 override 了 `bookPickerProvider` 和 `appServicesProvider`（不是 `AppServices.bootstrap()` / `%APPDATA%`）。因此它能证明 UI、仓库、SQLite、文件复制的组合链路，但不能替代真实应用进程启动和真实用户数据目录验收。“重开”是同一进程内关闭数据库、重建 Widget 并重新打开同一个临时目录，不是操作系统级进程重启。

### 4.4 Android 构建

- 构建必须在 ASCII 路径副本执行；仓库中文路径会触发 Gradle/NDK 路径问题（Phase 0 R-02）。
- `sqlite3` 3.8 默认从 GitHub 下载预编译 Android `.so`，本机网络超时。
- 解决方案：Android 使用 `eu.simonbinder:sqlite3-native-library:3.50.4`（Maven Central AAR）提供 `arm64-v8a` / `armeabi-v7a` / `x86_64` 的 `libsqlite3.so`；`sqlite3` hook 仅在 Android 使用 `system` 加载该库，Windows 保持包默认预编译库。
- APK 只包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三套 ABI；三者都含 `libsqlite3.so` 与 `libflutter.so`；`libsqlite3.so` 导出 `sqlite3_open` / `sqlite3_prepare_v2` / `sqlite3_close` 符号。
- APK 元数据：`app.moye.moye`、`versionName=1.4.0`、`minSdk=24`、`targetSdk=36`、应用名 `墨页`；APK 约 190 MiB（200,759,281 bytes）。
- `zipalign -c -P 16 -v 4` 校验通过；`lib/arm64-v8a/libsqlite3.so` 的 ELF LOAD 对齐为 `0x4000`。
- 最终 APK SHA-256：`ad47bb2b7fcf22a759792f179344bee7abb39396a45870301c82f629a80a4bfb`。检查明细见 [evidence/android-apk-check.txt](evidence/android-apk-check.txt)。
- **未验证**：APK 在 Android 真机/模拟器上的首次启动、数据库创建、文件选择器导入、删除。没有把构建成功等同于运行成功。

### 4.5 Windows 启动检查

`flutter build windows --debug` 成功，直接启动 `build/windows/x64/runner/Debug/moye.exe` 后进程保持运行，窗口标题为 Unicode `墨页`（码点 0x58A8、0x9875）。本轮 PowerShell 观察输出已保存到 [evidence/windows-launch.txt](evidence/windows-launch.txt)；该检查只验证启动与窗口，不替代 Android 运行验收。

## 5. 数据路径

Windows：

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

Android 使用 `getApplicationSupportDirectory()` 的应用私有目录，布局相同。数据库只存 `books/<uuid>.<ext>` 这类相对 POSIX 路径。

## 6. 已知限制与风险

| 风险 | 影响 | 当前处理 |
|---|---|---|
| Android 无真机运行验证 | 不能声称 Android 端验收通过 | 保留为 Phase 1 未关闭项；优先借真机或可用模拟器完成 |
| 中文仓库路径 | Android 构建失败；`flutter analyze` 崩溃 | 固定 ASCII 构建副本；长期建议迁移到 ASCII 工作路径或 CI |
| SQLite Android 预编译来源 | GitHub 不可达时构建失败 | 使用 Maven Central AAR；记录版本与来源；后续可改为本地源码编译 |
| 书籍文件与数据库非同一事务 | 极端崩溃时可能留下孤儿文件或已隔离文件 | 导入先落盘再写库，失败清理；删除先隔离再删库，失败恢复；启动 `reconcileQuarantine()` 恢复隔离区；`books/` 中无数据库记录的孤儿文件尚未自动清理 |
| 封面提取 | PDF 第一页、EPUB 封面、DOCX 首个内嵌图片；TXT/Markdown 使用全文排版封面 | 已实现；加密/扫描/损坏封面回退排版封面 |
| 尚未实现备份 | 不能跨设备迁移 | Phase 5 实现 `.moye`；备份时必须用 SQLite backup/checkpoint，不能直接复制活跃 WAL 数据库 |
| 搜索为 `LIKE` | 大书库性能有限 | Phase 2/3 再评估 FTS5；不在 Phase 1 过度设计 |

## 7. 下一阶段建议

Phase 2 阅读系统开始前，先完成两项：

1. **Android 运行验收**：在真机或可用模拟器完成一次启动、导入、重开、删除；若无法完成，必须由用户明确接受“仅构建验证”的风险。
2. **阅读器技术落点**：按 Phase 0 报告选定的 PDFium/Readium/DOCX 路线，先做单书阅读壳与位置恢复，不把标注、TTS 混入同一阶段。

Phase 2 的第一个可验收切片建议：

- 打开一本已导入 PDF；
- 渲染首页/连续滚动；
- 恢复最后阅读位置；
- 关闭重开仍能恢复；
- 在 Android 上至少验证一次页面渲染。

在此之前，不建议开始知识仓库或备份实现。

## 8. 产物

- Windows 调试构建：`build/windows/x64/runner/Debug/moye.exe`
- Android 调试 APK：`artifacts/phase-1/moye_phase1-debug.apk`
- APK SHA-256：`artifacts/phase-1/SHA256SUMS.txt`
- 构建/测试原始日志：`cache/phase1-*.log`（本地缓存，不进入版本库）

## 9. 结论

Phase 1 的代码与 Windows 可执行验收已经完成；Android 达到“可构建、APK 内容/对齐检查通过”，但未达到“可运行验收”。因此本报告不把 Phase 1 标为全平台完成，而是交给用户决定：

- 先补 Android 真机验证，再关闭 Phase 1；或
- 明确接受当前风险，进入 Phase 2，同时把 Android 运行验证作为 Phase 2 的第一个门禁。
